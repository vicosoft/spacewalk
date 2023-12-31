#!/usr/bin/perl -wT

$ENV{'PATH'} = '/bin:/usr/bin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

use Frontier::Client;
use Getopt::Long;
use Switch;
use List::MoreUtils qw(uniq);
use strict;

# This script is to post relevant errata from RHN to a Spacewalk server
#
# The method is to scrape the public errata archive at http://lists.centos.org/pipermail/centos-announce
# for the current months archive, parse through and find any errata ids.  The script will download the
# details via the RHN api (xmlrpc) https://rhn.redhat.com/rhn/apidoc/index.jsp and post the errata to a spacewalk
# server via the RHN api.  As always, YMMV.
#
# The earliest public CentOS errata is March 2005

# TODO
# 	- Have the errata only be published to channels where RPM exists
#	- Index all errata and not attempt to publish errata that is already published
#	- Apply errata updates
#	- Publish keywords from RHN (currently keywords are just package names)
#	- Make multithreaded (THIS IS A BIG MAYBE)


# MODES - Current month / year (default)
#		./get_errata
#		./get_errata --mode=cmonth
#         Current year (January to current month)
#		./get_errata --mode=cyear
#         Month span (assumes current year) current year
#		./get_errata --mode=mspan --start=jaNuAry --end=mArcH
#         Month span / year span
#		./get_errata --mode=myspan --start=jAnUary:2001 --end=mArCh:2006
#         Year span (January to December unless end year is current year, then end will be current month)
#		./get_errata --mode=yspan --start=2001 --end=2006
#         All
#		./get_errata --mode=all
#
# USAGE   ./get_errata --mode mode [--start month/year] [--end month/year]
#
#         modes
#		single - get single errata (NOTE: requires --errata erratanumber)
#		cmonth - current month
#		cyear  - current year
#		yspan  - year span (NOTE: requires options --start year (if --end is not passed, --end is current month/year))
#		all    - Gets all errata from start date March 2005 - current month / year
#
#
#

# Configuration Parameters
my $rhn_user = 'USER';
my $rhn_pass = 'PASSWORD';
my $spwk_user = 'admin';
my $spwk_pass = 'PASSWORD';
my $spacewalk_server='satelite.example.org';

# STATIC
my $digest_url = 'http://lists.centos.org/pipermail/centos-announce';
my $mode = '';
my $start = '';
my $end = '';
my $verbose = '';
my $errata_num = '';

GetOptions ('verbose' => \$verbose, 'mode=s' => \$mode, 'start=s' => \$start, 'end=s' => \$end, 'errata=s' => \$errata_num);

my @months = qw(January February March April May June July August September October November December);
(my $second, my $minute, my $hour, my $dayOfMonth, my $month, my $yearOffset, my $dayOfWeek, my $dayOfYear, my $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;

my $smonth;
my $syear;
my $emonth;
my $eyear;

if (!$mode) { $mode="cmonth"; }

switch ($mode) {

	case "cmonth"	{ 
				$smonth = $months[$month];
				$syear = $year;
				print "Current workload: $syear-$smonth\n************************\n";
				print "Processing $syear-$smonth\n";
				&process_errata("$syear-$smonth");
				&session_cleanup;
				exit;
			}

	case "single"	{	
				if (!$errata_num) { &help("Expected --errata erratanum"); }
				if (($errata_num !~ m/^RH/) || ($errata_num !~ m/:/) || ($errata_num =~ m/:$/)) {
					print "Skipping $errata_num\n";
					next;
				}
				&session_setup;
				print "Processing: $errata_num\n";
				my ($bugs_ref, $errata_info_ref) = pull_errata($errata_num);
				if((!$bugs_ref) || (!$errata_info_ref)) {
					next();
				}
				our @bugs = @$bugs_ref;
				our %errata_info = %$errata_info_ref;
				&push_errata(\@bugs, \%errata_info);
				&session_cleanup;
				exit;
			}

	case "cyear"	{
				$smonth = 0;
				$syear = $year;
				$emonth = $month;
				while ($smonth <= 11) {
					print "Current workload: $syear-$months[$smonth]\n************************\n";
					&process_errata("$syear-$months[$smonth]");
					$smonth++;
					if ($smonth > $emonth ) { last; }
				}
				&session_cleanup;
				exit;
			}

	case "yspan"	{	
				if (!$start) { &help("Expected --start=year"); }
				$smonth = 0;
				if ($start == 2005) { $smonth = 2; }
				$syear = $start;
				$emonth = 11;
				if (!$end) { $end = $year; }
				$eyear = $end;
				if ($syear > $eyear) { &help("Start year must not be greater then end year \(if no end year passed, current year is end year\)"); }
				while ($syear <= $eyear) {
					if ($smonth>11) { $smonth=0; }
					while ($smonth <= 11) {
						if (($syear == $year) && ($smonth > $month)) {
							last;
						}
						print "Current workload: $syear-$months[$smonth]\n************************\n";
						&process_errata("$syear-$months[$smonth]");
						$smonth++;
					}
					$syear++;
				}
				&session_cleanup;
				exit;
			}

	case "all"	{
				$smonth = 2;
				$syear = 2005;
				$emonth = $month;
				$eyear = $year;
				while ($syear <= $eyear) {
					if ($smonth>11) { $smonth=0; }
					while ($smonth <= 11) {
						if (($syear == $eyear) && ($smonth>$emonth)) {
							last;
						}
						print "Current workload: $syear-$months[$smonth]\n************************\n";
						&process_errata("$syear-$months[$smonth]");
						$smonth++;
					}
					$syear++;
				}
				&session_cleanup;
				exit;
			}

}

sub help {
	my $error = shift;
	print STDERR "Error occured: $error\n";
	exit(1);
}

sub session_setup {

	our $rhn_client = new Frontier::Client(url => "https://rhn.redhat.com/rpc/api/", debug => 0);
	our $rhn_session = $rhn_client->call('auth.login',$rhn_user, $rhn_pass);

	our $spwk_client = new Frontier::Client(url => "http://$spacewalk_server/rpc/api/", debug => 0);
	our $spwk_session = $spwk_client->call('auth.login',$spwk_user, $spwk_pass);
}

sub session_cleanup {
	our $rhn_session;
	our $spwk_session;
	our $rhn_client->call('auth.logout', $rhn_session); 
	our $spwk_client->call('auth.logout', $spwk_session); 
}

sub process_errata {

	my $digest_file = shift;
	my $rhn_errata_list;
	my $ce_errata_list1;
	my $ce_errata_list2;

	# These three gets are to account for the different ways errata is displayed in the CentOS announce lists

	open my $fh_rhn_errata_list, '-|' or exec "curl --silent http://lists.centos.org/pipermail/centos-announce/$digest_file.txt.gz | zcat | egrep -i 'RHSA\|RHBA\|RHEA' | grep http | sed -e 's/^.\\+errata\\///g' -e 's/-/:/2' | cut -d . -f1 | awk -F '-' {'print \$1\"-\"\$2'} | sort | uniq", @ARGV or die "curl failed: $!\n";
	foreach my $data (<$fh_rhn_errata_list>) {
	        $rhn_errata_list .= $data;
	}
	close $fh_rhn_errata_list;

	open my $fh_ce_errata_list1, '-|' or exec "curl --silent http://lists.centos.org/pipermail/centos-announce/$digest_file.txt.gz | zcat | egrep -i 'CESA\|CEBA\|CEEA' | grep Subject | awk {'print \$3'} | sed -e 's/CE/RH/g' | awk -F '-' {'print \$1\"-\"\$2'} | sort | uniq", @ARGV or die "curl failed: $!\n";
	foreach my $data (<$fh_ce_errata_list1>) {
		$ce_errata_list1 .= $data;
	}
	close $fh_ce_errata_list1;

	open my $fh_ce_errata_list2, '-|' or exec "curl --silent http://lists.centos.org/pipermail/centos-announce/$digest_file.txt.gz | zcat | egrep -i 'RHSA\|RHBA\|RHEA' | grep -v http | awk -F '-' {'print \$1\"-\"\$2'} | sort | uniq", @ARGV or die "curl failed: $!\n";
	foreach my $data (<$fh_ce_errata_list2>) {
		$ce_errata_list2 .= $data;
	}
	close $fh_ce_errata_list2;

	my $errata_list = $rhn_errata_list.$ce_errata_list1.$ce_errata_list1;
	$errata_list =~ s/[RH CE]....//g;
	$errata_list =~ s/(.{4})(.{1})(.*)/$1:$3/g;
	$errata_list =~ s/-*//g;
	$errata_list =~ s/^\s+|\s+$//g;

	my @errata_list = split /\n/, $errata_list;

	@errata_list = uniq(@errata_list);
	
	&session_setup;

	foreach my $errata (@errata_list) {
		my $found = '';
		my @types = qw(RHEA RHBA RHSA);
		foreach my $type (@types) {
			my $errata = "$type-$errata";
			print "Processing: $errata ";
			my ($bugs_ref, $errata_info_ref) = pull_errata($errata);
			if((!$bugs_ref) || (!$errata_info_ref)) {
				print " ....not found\n";
				next();
			} else {
				print " ....found\n";
			}
			our @bugs = @$bugs_ref;
			our %errata_info = %$errata_info_ref;
			&push_errata(\@bugs, \%errata_info);
			$found = $errata;
			last();
		}
		if (!$found) {
			print STDERR "Errata: $errata not processed\n\n";
		} else {
			print "Errata: $errata processed\n\n";
		}
	}

}

sub pull_errata {
	my $errata = shift;
	our $rhn_client;
	our $rhn_session;
	my $errata_details;

	eval { $errata_details = $rhn_client->call('errata.getDetails',$rhn_session,$errata); };
	if ($@) {
		return;
	}

	my @bugs = ( {"id" => 1, "summary" => $$errata_details{errata_synopsis} } );
	my %errata_info = ( "synopsis" => $$errata_details{errata_synopsis},
				"advisory_name" => $errata,
				"advisory_release" => 1,
				"advisory_type" => $$errata_details{errata_type},
				"product" => "Red Hat",
				"topic" => $$errata_details{errata_topic},
				"description" => $$errata_details{errata_description},
				"references" => $$errata_details{errata_references},
				"notes" => $$errata_details{errata_notes},
				"solution" => "Upgrade where applicable");

	return (\@bugs, \%errata_info);
}

sub push_errata {
	our @bugs = @bugs;
	our %errata_info = %errata_info;
	our $rhn_client;
	our $rhn_session;
	our $spwk_client;
	our $spwk_session;
	my @packages;
	my @keywords;
	my @channels;

	my @errata_packages = $rhn_client->call('errata.listPackages',$rhn_session,$errata_info{advisory_name});

	my @swchannels = $spwk_client->call('channel.listAllChannels',$spwk_session);

	foreach(@swchannels) {
		foreach (@$_) {
			my %channel = %{ $_ };
			push(@channels, $channel{label});
		}
	}

	foreach(@errata_packages) {
		foreach (@$_) {
			my %errata_package = %{ $_ };
			my @swpackages = $spwk_client->call('packages.findByNvrea',$spwk_session,$errata_package{package_name},$errata_package{package_version},$errata_package{package_release},"",$errata_package{package_arch_label});

			if($swpackages[0][0]{id}) {
				push(@keywords, $errata_package{package_name});
				push(@packages, $swpackages[0][0]{id});
			}
		}
	}

	@keywords = uniq(@keywords);

	eval {$spwk_client->call('errata.create',$spwk_session,\%errata_info,\@bugs,\@keywords,\@packages,1,\@channels) };

}
