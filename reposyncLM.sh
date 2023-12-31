#! /bin/sh -

# idiomatic parameter and option handling in sh
while test $# -gt 0
do
    case "$1" in
        --opt1) echo "option 1"
            ;;
        --opt2) echo "option 2"
            ;;
        --*) echo "bad option $1"
            ;;
        *) echo "argument $1"
            ;;
    esac
    shift
done


# /usr/bin/createrepo -g /var/lib/pulp/repos/redhat6/$1/comps.xml /var/lib/pulp/repos/redhat6/$1/
# /usr/bin/cp /var/cache/yum/x86_64/6Server/$1/gen/updateinfo.xml /var/lib/pulp/repos/redhat6/$1/repodata/
# /usr/bin/modifyrepo /var/lib/pulp/repos/redhat6/$1/repodata/updateinfo.xml /var/lib/pulp/repos/redhat6/$1/repodata/



exit 0
