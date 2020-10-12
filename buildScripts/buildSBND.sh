#!/bin/bash

# build sbndcode and sbndutil
# use mrb
# designed to work on Jenkins
# this is a proof of concept script

echo "sbndcode version: $SBND"
echo "base qualifiers: $QUAL"
echo "larsoft qualifiers: $LARSOFT_QUAL"
echo "build type: $BUILDTYPE"
echo "workspace: $WORKSPACE"

# Get number of cores to use.

if [ `uname` = Darwin ]; then
  #ncores=`sysctl -n hw.ncpu`
  #ncores=$(( $ncores / 4 ))
  ncores=1
else
  ncores=`cat /proc/cpuinfo 2>/dev/null | grep -c -e '^processor'`
fi
if [ $ncores -lt 1 ]; then
  ncores=1
fi
echo "Building using $ncores cores."

# Environment setup, uses /grid/fermiapp or cvmfs.

echo "ls /cvmfs/sbnd.opensciencegrid.org"
ls /cvmfs/sbnd.opensciencegrid.org
echo

if [ -f /grid/fermiapp/products/sbnd/setup_sbnd.sh ]; then
  source /grid/fermiapp/products/sbnd/setup_sbnd.sh || exit 1
elif [ -f /cvmfs/sbnd.opensciencegrid.org/products/setup_sbnd.sh ]; then
  if [ -x /cvmfs/grid.cern.ch/util/cvmfs-uptodate ]; then
    /cvmfs/grid.cern.ch/util/cvmfs-uptodate /cvmfs/sbnd.opensciencegrid.org/products
  fi
  source /cvmfs/sbnd.opensciencegrid.org/products/setup_sbnd.sh || exit 1
else
  echo "No setup file found."
  exit 1
fi
# skip around a version of mrb that does not work on macOS

if [ `uname` = Darwin ]; then
  if [[ x`which mrb | grep v1_17_02` != x ]]; then
    unsetup mrb || exit 1
    setup mrb v1_16_02 || exit 1
  fi
fi

# Use system git on macos.

if ! uname | grep -q Darwin; then
  setup git || exit 1
fi
setup gitflow || exit 1
export MRB_PROJECT=sbnd
echo "Mrb path:"
which mrb

set -x
rm -rf $WORKSPACE/temp || exit 1
mkdir -p $WORKSPACE/temp || exit 1
mkdir -p $WORKSPACE/copyBack || exit 1
rm -f $WORKSPACE/copyBack/* || exit 1
cd $WORKSPACE/temp || exit 1
mrb newDev  -v $SBND -q $QUAL:$BUILDTYPE || exit 1

set +x
source localProducts*/setup || exit 1

# some shenanigans so we can use getopt v1_1_6
if [ `uname` = Darwin ]; then
#  cd $MRB_INSTALL
#  curl --fail --silent --location --insecure -O http://scisoft.fnal.gov/scisoft/packages/getopt/v1_1_6/getopt-1.1.6-d13-x86_64.tar.bz2 || \
#      { cat 1>&2 <<EOF
#ERROR: pull of http://scisoft.fnal.gov/scisoft/packages/getopt/v1_1_6/getopt-1.1.6-d13-x86_64.tar.bz2 failed
#EOF
#        exit 1
#      }
#  tar xf getopt-1.1.6-d13-x86_64.tar.bz2 || exit 1
  setup getopt v1_1_6  || exit 1
#  which getopt
fi

set -x
cd $MRB_SOURCE  || exit 1
# make sure we get a read-only copy
mrb g -r -t $SBND sbndcode || exit 1

# Extract ubutil version from sbndcode product_deps
sbndutil_version=`grep sbndutil $MRB_SOURCE/sbndcode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
echo "sbnduitil version: $sbndutil_version"
mrb g -r -t $sbndutil_version sbndutil || exit 1

cd $MRB_BUILDDIR || exit 1
mrbsetenv || exit 1
mrb b -j$ncores || exit 1
if uname | grep -q Linux; then
  cp /usr/lib64/libXmu.so.6 sbndcode/lib
fi
mrb mp -n sbnd -- -j$ncores || exit 1

# add sbnd_data to the manifest

manifest=sbnd-*_MANIFEST.txt
sbnd_data_version=`grep sbnd_data $MRB_SOURCE/sbndcode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
sbnd_data_dot_version=`echo ${sbnd_data_version} | sed -e 's/_/./g' | sed -e 's/^v//'`
echo "sbnd_data          ${sbnd_data_version}       sbnd_data-${sbnd_data_dot_version}-noarch.tar.bz2" >>  $manifest

# Extract sbncode version from product_deps.
sbncode_version=`grep sbncode $MRB_SOURCE/sbndcode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
sbncode_dot_version=`echo ${sbncode_version} |  sed -e 's/_/./g' | sed -e 's/^v//'`


# Extract flavor.

flvr=''
if uname | grep -q Darwin; then
  flvr=`ups flavor -2`
else
  flvr=`ups flavor -4`
fi

# Construct name of sbncode manifest.

sbncode_hyphen_qual=`echo $QUAL | tr : - | sed 's/-noifdh//'`
sbncode_manifest=sbn-${sbncode_dot_version}-${flvr}-${sbncode_hyphen_qual}-${BUILDTYPE}_MANIFEST.txt
echo "sbncode manifest:"
echo $sbncode_manifest
echo

# Fetch sbncode manifest from scisoft and append to sbndcode manifest.

curl --fail --silent --location --insecure http://scisoft.fnal.gov/scisoft/bundles/sbn/${sbncode_version}/manifest/${sbncode_manifest} >> $manifest || exit 1

if echo $QUAL | grep -q noifdh; then
  if uname | grep -q Darwin; then
   # If this is a macos build, then rename the manifest to remove noifdh qualifier in the name
    noifdh_manifest=`echo $manifest | sed 's/-noifdh//'`
    mv $manifest $noifdh_manifest
  else
   # Otherwise (for slf builds), delete the manifest entirely.
    rm -f $manifest
  fi
fi

# Save artifacts.

mv *.bz2  $WORKSPACE/copyBack/ || exit 1
manifest=sbnd-*_MANIFEST.txt
if [ -f $manifest ]; then
  mv $manifest  $WORKSPACE/copyBack/ || exit 1
fi
cp $MRB_BUILDDIR/sbndcode/releaseDB/*.html $WORKSPACE/copyBack/
ls -l $WORKSPACE/copyBack/
cd $WORKSPACE || exit 1
rm -rf $WORKSPACE/temp || exit 1
set +x

exit 0
