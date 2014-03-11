#!/bin/bash
#
# updatenodes.sh -
#
# usage: updatefiles.sh [-h] [-a | -n nodename] [-v]
#
# Description: The updatenode.sh command runs on the management server 
#              to distribute /cf-root configuration files.
#              By default, the updatenode.sh command distributes
#              /cf-root configuration files on all cluster nodes.
#
# Prerequisites: ssh and rsync installed and configured passwordless 
#                on all cluster's nodes.
#
# ********************************************************************
# * 001 * 21-04-12 * Carmelo Ponti/CSCS Manno * File created         *
# * 002 * 29-10-12 *                          * ownership inherit and*
# * 003 *          *                          * symlink fixes        *
# ********************************************************************
#
# set -x

#---------------------------------------------------------------------
# CONFIGURATION
#---------------------------------------------------------------------

# Commands
ECHO=/bin/echo
CAT=/bin/cat
FIND=/usr/bin/find
GREP=/bin/grep
SORT=/usr/bin/sort
SED=/bin/sed
AWK=/usr/bin/awk
SSH=/usr/bin/ssh
SCP=/usr/bin/scp
RSYNC=/usr/bin/rsync
RM=/bin/rm
MKDIR=/bin/mkdir
CHMOD=/bin/chmod
CHOWN=/bin/chown
BASH=/bin/bash
STAT=/usr/bin/stat
LS=/bin/ls
TOUCH=/usr/bin/touch

# Names
CLUSTERNAME=clustername
WORKINGDIR=/cf-root
SEPARATOR='\\._'

#NODES=( node1 node2 node3 )
NODES=( `$CAT /etc/dsh/group/all` )
NODE=""
CFROOTUPDATE=0
VERBOSE=0

# Random number
NUMBER=$[ ( $RANDOM % 10000 )  + 1 ]

# Log files
LOG=/var/log/updatenode_all-`/bin/date +%Y%m`.log

# Temporary lists
# Files
CFROOTFILE=/tmp/cf-root_files.list_$NUMBER
CFROOTCOMFILE=/tmp/cf-root_commonfiles.list_$NUMBER
CFROOTSPECFILE=/tmp/cf-root_specificfiles.list_$NUMBER
# Directories
CFROOTDIR=/tmp/cf-root_directories.list_$NUMBER
CFROOTCOMDIR=/tmp/cf-root_commondirs.list_$NUMBER
CFROOTSPECDIR=/tmp/cf-root_specificdirs.list_$NUMBER
# Symlinks
CFROOTSYM=/tmp/cf-root_symlinks.list_$NUMBER
CFROOTCOMSYM=/tmp/cf-root_commonlinks.list_$NUMBER
CFROOTSPECSYM=/tmp/cf-root_specificlinks.list_$NUMBER
# Temporary
CFROOTTMPFILE=/tmp/cf-root_tmp_file.list_$NUMBER
CFROOTTMPSCRIPT=/tmp/cf-root_tmp_script.list_$NUMBER

#---------------------------------------------------------------------
# SUBROUTINES
#---------------------------------------------------------------------

function die() { $ECHO >&2 "$@"; exit 1; }

usage()
{
$CAT << EOF

Usage: $0 [-h] [-a | -n nodename] [-v]

Update /cf-root cluster nodes

OPTIONS:
   -h      Show this message
   -a      Distribute /cf-root files on all nodes (default)
   -n      Distribute /cf-root files only to <nodename> node
   -u      Update the management station /cf-root directory 
   -v      Verbose
EOF
}

function temporarylist()
{
  # Create all temporary copy lists
  #
  # Files
  $FIND $WORKINGDIR -type f | $SORT -n | $AWK -F/cf-root '{print $2}' | $SED 's/^\///' > $CFROOTFILE
  $CAT $CFROOTFILE | $GREP -v ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTCOMFILE
  $CAT $CFROOTFILE | $GREP ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTSPECFILE
  # Directories
  $FIND $WORKINGDIR -type d -empty | $SORT -n | $AWK -F/cf-root '{print $2}' | $SED 's/^\///' > $CFROOTDIR
  $CAT $CFROOTDIR | $GREP -v ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTCOMDIR
  $CAT $CFROOTDIR | $GREP ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTSPECDIR
  # Symlinks
  $FIND $WORKINGDIR -type l | $SORT -n | $AWK -F/cf-root '{print $2}' | $SED 's/^\///' > $CFROOTSYM
  $CAT $CFROOTSYM | $GREP -v ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTCOMSYM
  $CAT $CFROOTSYM | $GREP ._$CLUSTERNAME | $GREP -v ._EmptyGroup > $CFROOTSPECSYM
}

function cleantempfiles()
{
  $RM -f $CFROOTFILE
  $RM -f $CFROOTCOMFILE
  $RM -f $CFROOTSPECFILE
  $RM -f $CFROOTDIR
  $RM -f $CFROOTCOMDIR
  $RM -f $CFROOTSPECDIR
  $RM -f $CFROOTSYM
  $RM -f $CFROOTCOMSYM
  $RM -f $CFROOTSPECSYM
  $RM -f $CFROOTTMPFILE
  $RM -f $CFROOTTMPSCRIPT
}

function spread_common_files()
{
  if [ $VERBOSE == 1 ]
  then
     VER="-v"
  else
     VER=""
  fi
  #
  for HOST in ${NODES[@]}
  do
    if [ $VERBOSE == 1 ]
    then
      $ECHO "$RSYNC $VER -axu --relative --files-from=$CFROOTCOMFILE $WORKINGDIR $HOST:/"
    fi
    $RSYNC $VER -axu --relative --files-from=$CFROOTCOMFILE $WORKINGDIR $HOST:/
  done
}

function spread_specific_files()
{
  cd /cf-root
  if [ "X$NODE" == "X" ]
  then
    LIST=$CFROOTSPECFILE
  else
    $CAT $CFROOTSPECFILE | $GREP $NODE > $CFROOTTMPFILE
    LIST=$CFROOTTMPFILE
  fi
  #
  $CAT $LIST |\
  while read LINE 
  do
    FILE=`$ECHO $LINE | awk -F$SEPARATOR '{print $1}'`
    HOST=`$ECHO $LINE | awk -F$SEPARATOR '{print $2}'`
    $ECHO "$SCP -p $LINE $HOST:/$FILE" >> $CFROOTTMPSCRIPT
    $ECHO "$SSH $HOST $CHOWN `$STAT -c %u:%g $LINE` /$FILE" >> $CFROOTTMPSCRIPT
  done
  if [ $VERBOSE == 1 ]
  then
    $CAT $CFROOTTMPSCRIPT
  fi
  $CHMOD 750 $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $BASH $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPFILE > /dev/null 2>& 1
  cd ..
}

function spread_common_dirs()
{
#  $SED 1d $CFROOTCOMDIR |\
  $CAT $CFROOTCOMDIR |\
  while read LINE 
  do
    for HOST in ${NODES[@]}
    do
      $ECHO "$SSH $HOST $MKDIR -p /$LINE" >> $CFROOTTMPSCRIPT
      $ECHO "$SSH $HOST $CHOWN `$STAT -c %u:%g $WORKINGDIR/$LINE` /$LINE" >> $CFROOTTMPSCRIPT
      $ECHO "$SSH $HOST $CHMOD `$STAT -c %a $WORKINGDIR/$LINE` /$LINE" >> $CFROOTTMPSCRIPT
    done
  done
  if [ $VERBOSE == 1 ]
  then
    $CAT $CFROOTTMPSCRIPT
  fi
  $CHMOD 750 $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $BASH $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPSCRIPT > /dev/null 2>& 1
}

function spread_specific_dirs()
{
  # IMPORTANT: the current version handles specific 
  # directory only if empty
  #
  if [ "X$NODE" == "X" ]
  then
    LIST=$CFROOTSPECDIR
  else
    $CAT $CFROOTSPECDIR | $GREP $NODE > $CFROOTTMPFILE
    LIST=$CFROOTTMPFILE
  fi
  #
  $CAT $LIST |\
  while read LINE 
  do
    DIR=`$ECHO $LINE | awk -F$SEPARATOR '{print $1}'`
    HOST=`$ECHO $LINE | awk -F$SEPARATOR '{print $2}'`
    $ECHO "$SSH $HOST $MKDIR -p /$DIR" >> $CFROOTTMPSCRIPT
    $ECHO "$SSH $HOST $CHOWN `$STAT -c %u:%g $WORKINGDIR/$LINE` /$DIR" >> $CFROOTTMPSCRIPT
    $ECHO "$SSH $HOST $CHMOD `$STAT -c %a $WORKINGDIR/$LINE` /$DIR" >> $CFROOTTMPSCRIPT
  done
  if [ $VERBOSE == 1 ]
  then
    $CAT $CFROOTTMPSCRIPT > /dev/null 2>& 1
  fi
  $CHMOD 750 $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $BASH $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPSCRIPT > /dev/null 2>& 1
}

function spread_common_symlinks()
{
  echo "cd /cf-root" >> $CFROOTTMPSCRIPT 
  cd /cf-root
  $CAT $CFROOTCOMSYM |\
  while read LINE
  do
    for HOST in ${NODES[@]}
    do
      CMD=`$LS -l $LINE | $AWK '{print "/bin/ln -sT " $11" /"$9}'`
      $ECHO "$SSH $HOST $CMD" >> $CFROOTTMPSCRIPT
    done
  done
  echo "cd .." >> $CFROOTTMPSCRIPT
  cd ..
  if [ $VERBOSE == 1 ]
  then
    $CAT $CFROOTTMPSCRIPT > /dev/null 2>& 1
  fi
  $CHMOD 750 $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $BASH $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPSCRIPT > /dev/null 2>& 1
}

function spread_specific_symlinks()
{
  echo "cd /cf-root" >> $CFROOTTMPSCRIPT 
  cd /cf-root
  if [ "X$NODE" == "X" ]
  then
    LIST=$CFROOTSPECSYM
  else
    $CAT $CFROOTSPECSYM | $GREP $NODE > $CFROOTTMPFILE
    LIST=$CFROOTTMPFILE
  fi
  #
  $CAT $LIST |\
  while read LINE
  do
    FILE=`$ECHO $LINE | awk -F$SEPARATOR '{print $1}'`
    HOST=`$ECHO $LINE | awk -F$SEPARATOR '{print $2}'`
    CMD=`$LS -l $LINE | $AWK '{print "/bin/ln -sT " $11}'`
    $ECHO "$SSH $HOST $CMD /$FILE" >> $CFROOTTMPSCRIPT
  done
  echo "cd .." >> $CFROOTTMPSCRIPT
  cd ..
  if [ $VERBOSE == 1 ]
  then
    $CAT $CFROOTTMPSCRIPT > /dev/null 2>& 1
  fi
  $CHMOD 750 $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $BASH $CFROOTTMPSCRIPT > /dev/null 2>& 1
  $RM $CFROOTTMPSCRIPT > /dev/null 2>& 1
}

function cfrootupdate()
{
  $FIND $WORKINGDIR -type f -exec $TOUCH {} \; > /dev/null 2>& 1
}

#---------------------------------------------------------------------
# SCRIPT PROPER
#---------------------------------------------------------------------

# Getopts
while getopts "han:uv" OPT
do
  case $OPT in
    h)
      usage
      die
      ;;
    a)
      ;;
    n)
      NODES=( $OPTARG )
      NODE=$OPTARG
      LOG=/var/log/updatenode_$NODE-`/bin/date +%Y%m`.log
      ;;
    u)
      CFROOTUPDATE=1
      ;;
    v)
      VERBOSE=1
      ;;
    \?)
      $ECHO "Invalid option: -$OPTARG"
      die
      ;;
    :)
      usage
      die
      ;;
  esac
done

# Start logging file
if [ $VERBOSE == 0 ]
then
  exec >> $LOG 2>&1
fi

# Log start
$ECHO "---------------------------------------------------------------"
$ECHO "`basename $0`:" `/bin/date` 
$ECHO "==============================================================="

if [ $CFROOTUPDATE == 1 ]
then
   $ECHO "Updating management station /cf-root directory..."
   cfrootupdate
fi

$ECHO "Creating temporary list files..."
temporarylist

$ECHO "Spreading common files..."
spread_common_files
$ECHO "Spreading specific files..."
spread_specific_files
$ECHO "Spreading common directories..."
spread_common_dirs
$ECHO "Spreading specific directories..."
$ECHO "ATTENTION: only empty specific directories are allowed."
spread_specific_dirs
$ECHO "Spreading common symlinks..."
spread_common_symlinks
$ECHO "Spreading specific symlinks..."
spread_specific_symlinks

$ECHO "Cleaning temporary list files..."
cleantempfiles

# Log end
$ECHO "==============================================================="
$ECHO "`basename $0`:" `/bin/date`
$ECHO "---------------------------------------------------------------"
