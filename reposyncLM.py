#!/usr/bin/env python
import os
import sys
from time import ctime

def printusage():
        print "usage: reposyncLM.py <repo>"
        sys.exit()


def check_arg():
        try:
                host = sys.argv[1]
                if host.startswith("rhel-6-server-"):
                        try:
                                import socket
                                host = socket.gethostbyaddr(sys.argv[1].partition('[')[-1].rpartition(']')[0])[0]
                        except:
                                host = sys.argv[1].partition('[')[-1].rpartition(']')[0]
        except:
                printusage()



# We check the existence of the channel configuration file
# /usr/local/etc/reposyncLM.txt

def parse_config():
    """Parse the config file, return a list of the stuff
    we are supposed to sync (``SyncJob`` instances).
    The config file contains one sync job per line. Each line is a list
    of columns separted by whitespace.
    Currently, only two columns are expected: repository and push url.
    As an example, a line might look like this:
    /home/git/repos/reposync.git   git@github.com:miracle2k/reposync.git
    """
    config_path = None
    for path in ('.reposync.conf',
                 os.path.expanduser('~/.reposync.conf'),
                 '/etc/reposync.conf'):
        if os.path.exists(path):
            config_path = path
            break

    if not config_path:
        raise EnvironmentError("config file not found")

    result = []
    f = open(config_path, 'r');
    try:
        for line in f.readlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith('#'):
                continue
            bits = re.split(r'\s*', line)
            if len(bits) != 2:
                raise ValueError('Invalid line in config file: %s' % line)
            result.append(SyncJob(*bits))
    finally:
        f.close()

    return result




def repo_config():
    """We put the repositories in an array
    """

    for repo in ('rhel-6-server-rpms',
                 'rhel-6-server-extras-rpms',
                 'rhel-6-server-optional-rpms'):
        # we execute the creation of the repos...

    


save_out = sys.stdout
# Define the log file
f = "/tmp/reposync.log"
# Append to existing log file.
# Change 'a' to 'w' to recreate the log file each time.
fsock = open(f, 'a')
# Set stream to file
sys.stdout = fsock

# List of repositories
repos = os.listdir(r'/tmp/repos.txt')

# Read the list

for i in repos:
  os.system("/usr/bin/createrepo -g /var/lib/pulp/repos/redhat6/" + i + "/comps.xml /var/lib/pulp/repos/redhat6/" + i + "/")
  print ctime(), " :Sincronizado el repositorio ==> " + i
  os.system("/bin/cp /var/cache/yum/x86_64/6Server/" + i + "/gen/updateinfo.xml /var/lib/pulp/repos/redhat6/" + i + "/repodata/"
  print ctime(), " :Copiado el fichero updateinfo.xml en el repodata ==> " + i
  os.system("/usr/bin/modifyrepo /var/lib/pulp/repos/redhat6/" + i + "/repodata/updateinfo.xml /var/lib/pulp/repos/redhat6/" + i + "/repodata/")


sys.stdout = save_out
fsock.close()

