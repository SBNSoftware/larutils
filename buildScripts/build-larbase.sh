#!/bin/bash

# pull source code in $WORKSPACE/source
# build in $WORKSPACE/build
# copyback directory is $WORKSPACE/copyBack

usage()
{
  cat 1>&2 <<EOF
Usage: $(basename ${0}) [-h]
       $(basename ${0}) <version> <qual_set> <build_type>

Options:

  -h    This help.

Arguments:

  qual_set         Supported qualifier sets: s8:e7, s11:e7

EOF
}

while getopts :h OPT; do
  case ${OPT} in
    h)
      usage
      exit 1
      ;;
    *)
      usage
      exit 1
  esac
done
shift `expr $OPTIND - 1`
OPTIND=1

working_dir=${WORKSPACE}
version=${LARVER}
qual_set="${QUAL}"
build_type=${BUILDTYPE}

case ${qual_set} in
  s5:e5) 
     basequal=e5
     squal=s5
     artver=v1_12_04
     nuver=v1_07_00
  ;;
  s5:e6) 
     basequal=e6
     squal=s5
     artver=v1_12_04
     nuver=v1_07_00
  ;;
  s6:e6) 
     basequal=e6
     squal=s6
     artver=v1_12_05
     nuver=v1_07_01
  ;;
  s7:e7) 
     basequal=e7
     squal=s7
     artver=v1_13_01
     nuver=v1_09_01
  ;;
  s8:e7) 
     basequal=e7
     squal=s8
     artver=v1_13_02
     nuver=v1_10_02
  ;;
  s11:e7) 
     basequal=e7
     squal=s11
     artver=v1_14_02
     nuver=v1_11_01
  ;;
  s12:e7) 
     basequal=e7
     squal=s12
     artver=v1_14_03
     nuver=v1_13_01
  ;;
  s14:e7) 
     basequal=e7
     squal=s14
     artver=v1_15_01
     nuver=v1_14_01
  ;;
  s15:e7) 
     basequal=e7
     squal=s15
     artver=v1_15_02
     nuver=v1_14_05
  ;;
  s18:e9) 
     basequal=e9
     squal=s18
     artver=v1_16_02
     nuver=v1_15_02
  ;;
  s21:e9) 
     basequal=e9
     squal=s21
     artver=v1_17_03
     nuver=v1_16_01
  ;;
  *)
    usage
    exit 1
esac

case ${build_type} in
  debug) ;;
  prof) ;;
  *)
    usage
    exit 1
esac

# check XCode
if [[ `uname -s` == Darwin ]] 
then
  OSnum=`uname -r | cut -f1 -d"."`
  xver=`xcodebuild -version | grep Xcode | cut -f2 -d" " | cut -f1 -d"."`
  xcver=`xcodebuild -version | grep Xcode`
  if [[ ${basequal} == e9 ]] && [[ ${xver} < 7 ]] && [[ ${OSnum} > 13 ]]
  then
  echo "${basequal} build not supported on `uname -s`${OSnum} with ${xcver}"
  exit 0
  fi
fi

dotver=`echo ${version} | sed -e 's/_/./g' | sed -e 's/^v//'`

echo "building the larbase base distribution for ${version} ${dotver} ${qual_set} ${build_type}"

OS=`uname`
if [ "${OS}" = "Linux" ]
then
  flvr=slf`lsb_release -r | sed -e 's/[[:space:]]//g' | cut -f2 -d":" | cut -f1 -d"."`
elif [ "${OS}" = "Darwin" ]
then
  flvr=d`uname -r | cut -f1 -d"."`
else 
  echo "ERROR: unrecognized operating system ${OS}"
  exit 1
fi
echo "build flavor is ${flvr}"
echo ""

qualdir=`echo ${qual_set} | sed -e 's%:%-%'`

set -x

blddir=${working_dir}/build
srcdir=${working_dir}/source
# start with clean directories
rm -rf ${blddir}
rm -rf ${srcdir}
rm -rf $WORKSPACE/copyBack 
# now make the dfirectories
mkdir -p ${srcdir} || exit 1
mkdir -p ${blddir} || exit 1
mkdir -p $WORKSPACE/copyBack || exit 1

cd ${blddir} || exit 1
curl --fail --silent --location --insecure -O http://scisoft.fnal.gov/scisoft/bundles/tools/pullProducts || exit 1
chmod +x pullProducts
# source code tarballs MUST be pulled first
./pullProducts ${blddir} source larbase-${version} || \
      { cat 1>&2 <<EOF
ERROR: pull of larbase-${version} failed
EOF
        exit 1
      }
mv ${blddir}/*source* ${srcdir}/

cd ${blddir} || exit 1
# pulling binaries is allowed to fail
./pullProducts ${blddir} ${flvr} nubase-${nuver} ${basequal} ${build_type} 
./pullProducts ${blddir} ${flvr} nu-${nuver} ${squal}-${basequal} ${build_type} 
./pullProducts ${blddir} ${flvr} larbase-${version} ${squal}-${basequal} ${build_type} 
echo
echo "begin build"
echo
./buildFW -t -b ${basequal} -s ${squal} ${blddir} ${build_type} larbase-${version} || \
 { mv ${blddir}/*.log  $WORKSPACE/copyBack/
   exit 1 
 }

echo
echo "move files"
echo
mv ${blddir}/*.bz2  $WORKSPACE/copyBack/
mv ${blddir}/*.txt  $WORKSPACE/copyBack/

exit 0
