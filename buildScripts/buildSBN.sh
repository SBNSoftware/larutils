#!/bin/bash

# build sbncode
# use mrb
# designed to work on Jenkins
# this is a proof of concept script

echo "sbncode version: $SBN"
echo "base qualifiers: $QUAL"
echo "s qualifier: $SQUAL"
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

# Environment setup, uses cvmfs.

echo "ls /cvmfs/larsoft.opensciencegrid.org"
ls /cvmfs/larsoft.opensciencegrid.org
echo

if [ -f /cvmfs/larsoft.opensciencegrid.org/products/setup ]; then
  if [ -x /cvmfs/grid.cern.ch/util/cvmfs-uptodate ]; then
    /cvmfs/grid.cern.ch/util/cvmfs-uptodate /cvmfs/larsoft.opensciencegrid.org/products
  fi
  source /cvmfs/larsoft.opensciencegrid.org/products/setup || exit 1
else
  echo "No larsoft setup file found."
  exit 1
fi

if [ -f /cvmfs/sbn.opensciencegrid.org/products/sbn/setup ]; then
  if [ -x /cvmfs/grid.cern.ch/util/cvmfs-uptodate ]; then
    /cvmfs/grid.cern.ch/util/cvmfs-uptodate /cvmfs/sbn.opensciencegrid.org/products/sbn
  fi
  source /cvmfs/sbn.opensciencegrid.org/products/sbn/setup || exit 1
else
  echo "No sbn setup file found."
  exit 1
fi

#setup mrb
setup mrb || exit 1

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
export MRB_PROJECT=sbn
echo "Mrb path:"
which mrb

set -x
rm -rf $WORKSPACE/temp || exit 1
mkdir -p $WORKSPACE/temp || exit 1
mkdir -p $WORKSPACE/copyBack || exit 1
rm -f $WORKSPACE/copyBack/* || exit 1
cd $WORKSPACE/temp || exit 1
mrb newDev  -v $SBN -q $QUAL:$BUILDTYPE || exit 1

set +x
source localProducts*/setup || exit 1

if [ `uname` = Darwin ]; then
  setup getopt v1_1_6  || exit 1
fi

set -x
cd $MRB_SOURCE  || exit 1
# make sure we get a read-only copy
mrb g -r -t $SBN sbncode || exit 1

# Extract sbnobj version from sbncode product_deps
sbnobj_version=`grep sbnobj $MRB_SOURCE/sbncode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
echo "sbnobj version: $sbnobj_version"
mrb g -r -t $sbnobj_version sbnobj || exit 1

# Extract sbndaq_artdaq_core version from sbncode product_deps
sbndaq_artdaq_core_version=`grep sbndaq_artdaq_core $MRB_SOURCE/sbncode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
echo "sbndaq_artdaq_core version: $sbndaq_artdaq_core_version"
mrb g -r -t $sbndaq_artdaq_core_version sbndaq_artdaq_core || exit 1

cd $MRB_BUILDDIR || exit 1
mrbsetenv || exit 1
mrb b -j$ncores || exit 1
if uname | grep -q Linux; then
  cp /usr/lib64/libXmu.so.6 sbncode/lib
fi
mrb mp -n sbn -- -j$ncores || exit 1

manifest=sbn-*_MANIFEST.txt

# Extract larsoft version from product_deps.
larsoft_version=`grep larsoft $MRB_SOURCE/sbncode/ups/product_deps | grep -v qualifier | awk '{print $2}'`
larsoft_dot_version=`echo ${larsoft_version} |  sed -e 's/_/./g' | sed -e 's/^v//'`

# Extract flavor.

flvr=''
if uname | grep -q Darwin; then
  flvr=`ups flavor -2`
else
  flvr=`ups flavor -4`
fi

# Construct name of larsoft manifest.

larsoft_hyphen_qual=`echo $SQUAL:$QUAL | tr : - | sed 's/-noifdh//'`
larsoft_manifest=larsoft-${larsoft_dot_version}-${flvr}-${larsoft_hyphen_qual}-${BUILDTYPE}_MANIFEST.txt
echo "Larsoft manifest:"
echo $larsoft_manifest
echo

# Fetch larsoft manifest from scisoft and append to sbncode manifest.

curl --fail --silent --location --insecure http://scisoft.fnal.gov/scisoft/bundles/larsoft/${larsoft_version}/manifest/${larsoft_manifest} >> $manifest || exit 1

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
manifest=sbn-*_MANIFEST.txt
if [ -f $manifest ]; then
  mv $manifest  $WORKSPACE/copyBack/ || exit 1
fi
cp $MRB_BUILDDIR/sbncode/releaseDB/*.html $WORKSPACE/copyBack/
ls -l $WORKSPACE/copyBack/
cd $WORKSPACE || exit 1
rm -rf $WORKSPACE/temp || exit 1
set +x

exit 0
