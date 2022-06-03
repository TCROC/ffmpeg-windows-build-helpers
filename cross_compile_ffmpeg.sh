#!/usr/bin/env bash
# ffmpeg windows cross compile helper/download script, see github repo README
# Copyright (C) 2012 Roger Pack, the script is under the GPLv3, but output FFmpeg's executables aren't
# set -x

yes_no_sel () {
  unset user_input
  local question="$1"
  shift
  local default_answer="$1"
  while [[ "$user_input" != [YyNn] ]]; do
    echo -n "$question"
    read user_input
    if [[ -z "$user_input" ]]; then
      echo "using default $default_answer"
      user_input=$default_answer
    fi
    if [[ "$user_input" != [YyNn] ]]; then
      clear; echo 'Your selection was not vaild, please try again.'; echo
    fi
  done
  # downcase it
  user_input=$(echo $user_input | tr '[A-Z]' '[a-z]')
}

set_box_memory_size_bytes() {
  if [[ $OSTYPE == darwin* ]]; then
    box_memory_size_bytes=20000000000 # 20G fake it out for now :|
  else
    local ram_kilobytes=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    local swap_kilobytes=`grep SwapTotal /proc/meminfo | awk '{print $2}'`
    box_memory_size_bytes=$[ram_kilobytes * 1024 + swap_kilobytes * 1024]
  fi
}

function sortable_version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

at_least_required_version() { # params: required actual
  local sortable_required=$(sortable_version $1)
  sortable_required=$(echo $sortable_required | sed 's/^0*//') # remove preceding zeroes, which bash later interprets as octal or screwy
  local sortable_actual=$(sortable_version $2)
  sortable_actual=$(echo $sortable_actual | sed 's/^0*//')
  [[ "$sortable_actual" -ge "$sortable_required" ]]
}

apt_not_installed() {
  for x in "$@"; do
    if ! dpkg -l "$x" | grep -q '^.i'; then
      need_install="$need_install $x"
    fi
  done
  echo "$need_install"
}

check_missing_packages () {
  # We will need this later if we don't want to just constantly be grepping the /etc/os-release file
  if [ -z "${VENDOR}" ] && grep -E '(centos|rhel)' /etc/os-release &> /dev/null; then
    # In RHEL this should always be set anyway. But not so sure about CentOS
    VENDOR="redhat"
  fi
  # zeranoe's build scripts use wget, though we don't here...
  local check_packages=('ragel' 'curl' 'pkg-config' 'make' 'git' 'svn' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'makeinfo' 'g++' 'ed' 'pax' 'unzip' 'patch' 'wget' 'xz' 'nasm' 'gperf' 'autogen' 'bzip2' 'realpath' 'meson' 'clang' 'python')
  # autoconf-archive is just for leptonica FWIW
  # I'm not actually sure if VENDOR being set to centos is a thing or not. On all the centos boxes I can test on it's not been set at all.
  # that being said, if it where set I would imagine it would be set to centos... And this contition will satisfy the "Is not initially set"
  # case because the above code will assign "redhat" all the time.
  if [ -z "${VENDOR}" ] || [ "${VENDOR}" != "redhat" ] && [ "${VENDOR}" != "centos" ]; then
    check_packages+=('cmake')
  fi
  # libtool check is wonky...
  if [[ $OSTYPE == darwin* ]]; then
    check_packages+=('glibtoolize') # homebrew special :|
  else
    check_packages+=('libtoolize') # the rest of the world
  fi
  # Use hash to check if the packages exist or not. Type is a bash builtin which I'm told behaves differently between different versions of bash.
  for package in "${check_packages[@]}"; do
    hash "$package" &> /dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done
  if [ "${VENDOR}" = "redhat" ] || [ "${VENDOR}" = "centos" ]; then
    if [ -n "$(hash cmake 2>&1)" ] && [ -n "$(hash cmake3 2>&1)" ]; then missing_packages=('cmake' "${missing_packages[@]}"); fi
  fi
  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs (svn is actually package subversion, makeinfo is actually package texinfo if you're missing them): ${missing_packages[*]}"
    echo 'Install the missing packages before running this script.'
    determine_distro

    apt_pkgs='subversion ragel curl texinfo g++ ed bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev unzip pax nasm gperf autogen bzip2 autoconf-archive p7zip-full meson clang'

    [[ $DISTRO == "debian" ]] && apt_pkgs="$apt_pkgs libtool-bin ed" # extra for debian
    case "$DISTRO" in
      Ubuntu)
        echo "for ubuntu:"
        echo "$ sudo apt-get update"
        ubuntu_ver="$(lsb_release -rs)"
        if at_least_required_version "18.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs python3-distutils" # guess it's no longer built-in, lensfun requires it...
        fi
        if at_least_required_version "20.04" "$ubuntu_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        echo "$ sudo apt-get install $apt_pkgs -y"
        if uname -a | grep  -q -- "-microsoft" ; then
         echo NB if you use WSL Ubuntu 20.04 you need to do an extra step: https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452
	fi
        ;;
      debian)
        echo "for debian:"
        echo "$ sudo apt-get update"
        # Debian version is always encoded in the /etc/debian_version
        # This file is deployed via the base-files package which is the essential one - deployed in all installations.
        # See their content for individual debian releases - https://sources.debian.org/src/base-files/
        # Stable releases contain a version number.
        # Testing/Unstable releases contain a textual codename description (e.g. bullseye/sid)
        #
        deb_ver="$(cat /etc/debian_version)"
        # Upcoming codenames taken from https://en.wikipedia.org/wiki/Debian_version_history
        #
        if [[ $deb_ver =~ bullseye ]]; then
            deb_ver="11"
        elif [[ $deb_ver =~ bookworm ]]; then
            deb_ver="12"
        elif [[ $deb_ver =~ trixie ]]; then
            deb_ver="13"
        fi
        if at_least_required_version "10" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python3-distutils" # guess it's no longer built-in, lensfun requires it...
        fi
        if at_least_required_version "11" "$deb_ver"; then
          apt_pkgs="$apt_pkgs python-is-python3" # needed
        fi
        apt_missing="$(apt_not_installed "$apt_pkgs")"
        echo "$ sudo apt-get install $apt_missing -y"
        ;;
      *)
        echo "for OS X (homebrew): brew install ragel wget cvs yasm autogen automake autoconf cmake libtool xz pkg-config nasm bzip2 autoconf-archive p7zip coreutils meson llvm" # if edit this edit docker/Dockerfile also :|
        echo "   and set llvm to your PATH if on catalina"
        echo "for RHEL/CentOS: First ensure you have epel repo available, then run $ sudo yum install ragel subversion texinfo libtool autogen gperf nasm patch unzip pax ed gcc-c++ bison flex yasm automake autoconf gcc zlib-devel cvs bzip2 cmake3 -y"
        echo "for fedora: if your distribution comes with a modern version of cmake then use the same as RHEL/CentOS but replace cmake3 with cmake."
        echo "for linux native compiler option: same as <your OS> above, also add libva-dev"
        ;;
    esac
    exit 1
  fi

  export REQUIRED_CMAKE_VERSION="3.0.0"
  for cmake_binary in 'cmake' 'cmake3'; do
    # We need to check both binaries the same way because the check for installed packages will work if *only* cmake3 is installed or
    # if *only* cmake is installed.
    # On top of that we ideally would handle the case where someone may have patched their version of cmake themselves, locally, but if
    # the version of cmake required move up to, say, 3.1.0 and the cmake3 package still only pulls in 3.0.0 flat, then the user having manually
    # installed cmake at a higher version wouldn't be detected.
    if hash "${cmake_binary}"  &> /dev/null; then
      cmake_version="$( "${cmake_binary}" --version | sed -e "s#${cmake_binary}##g" | head -n 1 | tr -cd '[0-9.\n]' )"
      if at_least_required_version "${REQUIRED_CMAKE_VERSION}" "${cmake_version}"; then
        export cmake_command="${cmake_binary}"
        break
      else
        echo "your ${cmake_binary} version is too old ${cmake_version} wanted ${REQUIRED_CMAKE_VERSION}"
      fi
    fi
  done

  # If cmake_command never got assigned then there where no versions found which where sufficient.
  if [ -z "${cmake_command}" ]; then
    echo "there where no appropriate versions of cmake found on your machine."
    exit 1
  else
    # If cmake_command is set then either one of the cmake's is adequate.
    if [[ $cmake_command != "cmake" ]]; then # don't echo if it's the normal default
      echo "cmake binary for this build will be ${cmake_command}"
    fi
  fi

  if [[ ! -f /usr/include/zlib.h ]]; then
    echo "warning: you may need to install zlib development headers first if you want to build mp4-box [on ubuntu: $ apt-get install zlib1g-dev] [on redhat/fedora distros: $ yum install zlib-devel]" # XXX do like configure does and attempt to compile and include zlib.h instead?
    sleep 1
  fi

  # TODO nasm version :|

  # doing the cut thing with an assigned variable dies on the version of yasm I have installed (which I'm pretty sure is the RHEL default)
  # because of all the trailing lines of stuff
  export REQUIRED_YASM_VERSION="1.2.0" # export ???
  local yasm_binary=yasm
  local yasm_version="$( "${yasm_binary}" --version |sed -e "s#${yasm_binary}##g" | head -n 1 | tr -dc '[0-9.\n]' )"
  if ! at_least_required_version "${REQUIRED_YASM_VERSION}" "${yasm_version}"; then
    echo "your yasm version is too old $yasm_version wanted ${REQUIRED_YASM_VERSION}"
    exit 1
  fi
  local meson_version=`meson --version`
  if ! at_least_required_version "0.49.2" "${meson_version}"; then
    echo "your meson version is too old $meson_version wanted 0.49.2"
    exit 1
  fi
  # also check missing "setup" so it's early LOL

  #check if WSL
  # check WSL for interop setting make sure its disabled
  # check WSL for kernel version look for version 4.19.128 current as of 11/01/2020
  if uname -a | grep  -q -- "-microsoft" ; then
    if cat /proc/sys/fs/binfmt_misc/WSLInterop | grep -q enabled ; then
      echo "windows WSL detected: you must first disable 'binfmt' by running this
      sudo bash -c 'echo 0 > /proc/sys/fs/binfmt_misc/WSLInterop'
      then try again"
      exit 1
    fi
    export MINIMUM_KERNEL_VERSION="4.19.128"
    KERNVER=$(uname -a | awk -F'[ ]' '{ print $3 }' | awk -F- '{ print $1 }')

    function version { # for version comparison @ stackoverflow.com/a/37939589
      echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
    }

    if [ $(version $KERNVER) -lt $(version $MINIMUM_KERNEL_VERSION) ]; then
      echo "Windows Subsystem for Linux (WSL) detected - kernel not at minumum version required: $MINIMUM_KERNEL_VERSION
      Please update via windows update then try again"
      exit 1
    fi
    echo "for WSL ubuntu 20.04 you need to do an extra step https://github.com/rdp/ffmpeg-windows-build-helpers/issues/452"
  fi

}

determine_distro() {

# Determine OS platform from https://askubuntu.com/a/459425/20972
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        export DISTRO=$(grep '^ID' /etc/os-release | sed 's#.*=\(\)#\1#')
    fi
fi
# For everything else (or if above failed), just use generic identifier
[ "$DISTRO" == "" ] && export DISTRO=$UNAME
unset UNAME
}


intro() {
  cat <<EOL
     ##################### Welcome ######################
  Welcome to the ffmpeg cross-compile builder-helper script.
  Downloads and builds will be installed to directories within $cur_dir
  If this is not ok, then exit now, and cd to the directory where you'd
  like them installed, then run this script again from there.
  NB that once you build your compilers, you can no longer rename/move
  the sandbox directory, since it will have some hard coded paths in there.
  You can, of course, rebuild ffmpeg from within it, etc.
EOL
  echo `date` # for timestamping super long builds LOL
  if [[ $sandbox_ok != 'y' && ! -d sandbox ]]; then
    echo
    echo "Building in $PWD/sandbox, will use ~ 12GB space!"
    echo
  fi
  mkdir -p "$cur_dir"
  cd "$cur_dir"
  if [[ $disable_nonfree = "y" ]]; then
    non_free="n"
  else
    if  [[ $disable_nonfree = "n" ]]; then
      non_free="y"
    else
      yes_no_sel "Would you like to include non-free (non GPL compatible) libraries, like [libfdk_aac,decklink -- note that the internal AAC encoder is ruled almost as high a quality as fdk-aac these days]
The resultant binary may not be distributable, but can be useful for in-house use. Include these non-free license libraries [y/N]?" "n"
      non_free="$user_input" # save it away
    fi
  fi
  echo "sit back, this may take awhile..."
}

pick_compiler_flavors() {
  while [[ "$compiler_flavors" != [1-5] ]]; do
    if [[ -n "${unknown_opts[@]}" ]]; then
      echo -n 'Unknown option(s)'
      for unknown_opt in "${unknown_opts[@]}"; do
        echo -n " '$unknown_opt'"
      done
      echo ', ignored.'; echo
    fi
    cat <<'EOF'
What version of MinGW-w64 would you like to build or update?
  1. Both Win32 and Win64
  2. Win32 (32-bit only)
  3. Win64 (64-bit only)
  4. Local native
  5. Exit
EOF
    echo -n 'Input your choice [1-5]: '
    read compiler_flavors
  done
  case "$compiler_flavors" in
  1 ) compiler_flavors=multi ;;
  2 ) compiler_flavors=win32 ;;
  3 ) compiler_flavors=win64 ;;
  4 ) compiler_flavors=native ;;
  5 ) echo "exiting"; exit 0 ;;
  * ) clear;  echo 'Your choice was not valid, please try again.'; echo ;;
  esac
}

# made into a method so I don't/don't have to download this script every time if only doing just 32 or just6 64 bit builds...
download_gcc_build_script() {
    local zeranoe_script_name=$1
    rm -f $zeranoe_script_name || exit 1
    curl -4 file://$patch_dir/$zeranoe_script_name -O --fail || exit 1
    chmod u+x $zeranoe_script_name
}

install_cross_compiler() {
  local win32_gcc="cross_compilers/mingw-w64-i686/bin/i686-w64-mingw32-gcc"
  local win64_gcc="cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-gcc"
  if [[ -f $win32_gcc && -f $win64_gcc ]]; then
   echo "MinGW-w64 compilers both already installed, not re-installing..."
   if [[ -z $compiler_flavors ]]; then
     echo "selecting multi build (both win32 and win64)...since both cross compilers are present assuming you want both..."
     compiler_flavors=multi
   fi
   return # early exit they've selected at least some kind by this point...
  fi

  if [[ -z $compiler_flavors ]]; then
    pick_compiler_flavors
  fi
  if [[ $compiler_flavors == "native" ]]; then
    echo "native build, not building any cross compilers..."
    return
  fi

  mkdir -p cross_compilers
  cd cross_compilers

    unset CFLAGS # don't want these "windows target" settings used the compiler itself since it creates executables to run on the local box (we have a parameter allowing them to set them for the script "all builds" basically)
    # pthreads version to avoid having to use cvs for it
    echo "Starting to download and build cross compile version of gcc [requires working internet access] with thread count $gcc_cpu_count..."
    echo ""

    # --disable-shared allows c++ to be distributed at all...which seemed necessary for some random dependency which happens to use/require c++...
    local zeranoe_script_name=mingw-w64-build-r22.local
    local zeranoe_script_options="--gcc-ver=10.2.0 --mingw-w64-ver=9.0.0 --default-configure --cpu-count=$gcc_cpu_count --disable-shared --clean-build --verbose --allow-overwrite --threads=winpthreads" # allow-overwrite to avoid some crufty prompts if I do rebuilds [or maybe should just nuke everything...]
    if [[ ($compiler_flavors == "win32" || $compiler_flavors == "multi") && ! -f ../$win32_gcc ]]; then
      echo "Building win32 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      if [[ `uname` =~ "5.1" ]]; then # Avoid using secure API functions for compatibility with msvcrt.dll on Windows XP.
        sed -i "s/ --enable-secure-api//" $zeranoe_script_name
      fi
      nice ./$zeranoe_script_name $zeranoe_script_options --build-type=win32 || exit 1
      if [[ ! -f ../$win32_gcc ]]; then
        echo "Failure building 32 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
      if [[ ! -f  ../cross_compilers/mingw-w64-i686/i686-w64-mingw32/lib/libmingwex.a ]]; then
	      echo "failure building mingwex? 32 bit"
	      exit 1
      fi
    fi
    if [[ ($compiler_flavors == "win64" || $compiler_flavors == "multi") && ! -f ../$win64_gcc ]]; then
      echo "Building win64 x86_64 cross compiler..."
      download_gcc_build_script $zeranoe_script_name
      nice ./$zeranoe_script_name $zeranoe_script_options --build-type=win64 || exit 1
      if [[ ! -f ../$win64_gcc ]]; then
        echo "Failure building 64 bit gcc? Recommend nuke sandbox (rm -rf sandbox) and start over..."
        exit 1
      fi
      if [[ ! -f  ../cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32/lib/libmingwex.a ]]; then
	      echo "failure building mingwex? 64 bit"
	      exit 1
      fi
    fi

    # rm -f build.log # leave resultant build log...sometimes useful...
    reset_cflags
  cd ..
  echo "Done building (or already built) MinGW-w64 cross-compiler(s) successfully..."
  echo `date` # so they can see how long it took :)
}

# helper methods for downloading and building projects that can take generic input

do_svn_checkout() {
  repo_url="$1"
  to_dir="$2"
  desired_revision="$3"
  if [ ! -d $to_dir ]; then
    echo "svn checking out to $to_dir"
    if [[ -z "$desired_revision" ]]; then
      svn checkout $repo_url $to_dir.tmp  --non-interactive --trust-server-cert || exit 1
    else
      svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
    fi
    mv $to_dir.tmp $to_dir
  else
    cd $to_dir
    echo "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
    # XXX accomodate for desired revision here if I ever uncomment the next line...
    # svn up
    cd ..
  fi
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    to_dir=$(basename $repo_url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  fi
  local desired_branch="$3"
  local branchCommand=""

  # reset will be useless if they didn't git_get_latest but pretty fast so who cares...plus what if they changed branches? :)
  # old_git_version=`git rev-parse HEAD`
  if [[ -n $desired_branch ]]; then
    branchCommand="-b $desired_branch --single-branch"
  fi

  echo "Downloading (via git clone) $to_dir from $repo_url"
  rm -rf $to_dir.tmp # just in case it was interrupted previously...
  git clone $branchCommand --depth 1 $repo_url $to_dir.tmp || exit 1
  # prevent partial checkouts by renaming it only after success
  mv $to_dir.tmp $to_dir
  echo "done git cloning to $to_dir"
  cd $to_dir

  # echo "doing git checkout $desired_branch"
  # git -c 'advice.detachedHead=false' checkout "$desired_branch" || (git_hard_reset && git -c 'advice.detachedHead=false' checkout "$desired_branch") || (git reset --hard "$desired_branch") || exit 1 # can't just use merge -f because might "think" patch files already applied when their changes have been lost, etc...
  # # vmaf on 16.04 needed that weird reset --hard? huh?
  # if git show-ref --verify --quiet "refs/remotes/origin/$desired_branch"; then # $desired_branch is actually a branch, not a tag or commit
  #   git merge "origin/$desired_branch" || exit 1 # get incoming changes to a branch
  # fi
  # new_git_version=`git rev-parse HEAD`
  # if [[ "$old_git_version" != "$new_git_version" ]]; then
  #   echo "got upstream changes, forcing re-configure. Doing git clean"
  #   git_hard_reset
  # else
  #   echo "fetched no code changes, not forcing reconfigure for that..."
  # fi
  # cd ..
}

git_hard_reset() {
  git reset --hard # throw away results of patch files
  git clean -fx # throw away local changes; 'already_*' and bak-files for instance.
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS $LDFLAGS | /usr/bin/env md5sum)" # md5sum to make it smaller, cflags to force rebuild if changes
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
}

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name")
  if [ ! -f "$touch_name" ]; then
    # make uninstall # does weird things when run under ffmpeg src so disabled for now...

    echo "configuring $english_name ($PWD) as $ PKG_CONFIG_PATH=$PKG_CONFIG_PATH PATH=$mingw_bin_path:\$PATH $configure_name $configure_options" # say it now in case bootstrap fails etc.
    echo "all touch files" already_configured* touchname= "$touch_name"
    echo "config options "$configure_options $configure_name""
    if [ -f bootstrap ]; then
      ./bootstrap # some need this to create ./configure :|
    fi
    if [[ ! -f $configure_name && -f bootstrap.sh ]]; then # fftw wants to only run this if no configure :|
      ./bootstrap.sh
    fi
    if [[ ! -f $configure_name ]]; then
      autoreconf -fiv # a handful of them require this to create ./configure :|
    fi
    rm -f already_* # reset
    nice -n 5 "$configure_name" $configure_options || { echo "failed configure $english_name"; exit 1;} # less nicey than make (since single thread, and what if you're running another ffmpeg nice build elsewhere?)
    touch -- "$touch_name"
    echo "doing preventative make clean"
    nice make clean -j $cpu_count # sometimes useful when files change, etc.
  #else
  #  echo "already configured $(basename $cur_dir2)"
  fi
}

do_make() {
  local extra_make_options="$1 -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options" )

  if [ ! -f $touch_name ]; then
    echo
    echo "Making $cur_dir2 as $ PATH=$mingw_bin_path:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "Already made $(dirname "$cur_dir2") $(basename "$cur_dir2") ..."
  fi
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_install_options"
  else
    local make_install_options="$override_make_install_options $extra_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$mingw_bin_path:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake() {
  extra_args="$1"
  local build_from_dir="$2"
  if [[ -z $build_from_dir ]]; then
    build_from_dir="."
  fi
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    echo doing cmake in $cur_dir2 with PATH=$mingw_bin_path:\$PATH with extra_args=$extra_args like this:
    if [[ $compiler_flavors != "native" ]]; then
      local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_FIND_ROOT_PATH=$mingw_w64_x86_64_prefix -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_RANLIB=${cross_prefix}ranlib -DCMAKE_C_COMPILER=${cross_prefix}gcc -DCMAKE_CXX_COMPILER=${cross_prefix}g++ -DCMAKE_RC_COMPILER=${cross_prefix}windres -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args"
    else
      local command="${build_from_dir} -DENABLE_STATIC_RUNTIME=1 -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$mingw_w64_x86_64_prefix $extra_args"
    fi
    echo "doing ${cmake_command}  -G\"Unix Makefiles\" $command"
    nice -n 5  ${cmake_command} -G"Unix Makefiles" $command || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_from_build_dir() { # some sources don't allow it, weird XXX combine with the above :)
  source_dir="$1"
  extra_args="$2"
  do_cmake "$extra_args" "$source_dir"
}

do_cmake_and_install() {
  do_cmake "$1"
  do_make_and_make_install
}

do_meson() {
    local configure_options="$1 --unity=off"
    local configure_name="$2"
    local configure_env="$3"
    local configure_noclean=""
    if [[ "$configure_name" = "" ]]; then
        configure_name="meson"
    fi
    local cur_dir2=$(pwd)
    local english_name=$(basename $cur_dir2)
    local touch_name=$(get_small_touchfile_name already_built_meson "$configure_options $configure_name $LDFLAGS $CFLAGS")
    if [ ! -f "$touch_name" ]; then
        if [ "$configure_noclean" != "noclean" ]; then
            make clean # just in case
        fi
        rm -f already_* # reset
        echo "Using meson: $english_name ($PWD) as $ PATH=$PATH ${configure_env} $configure_name $configure_options"
        #env
        "$configure_name" $configure_options || exit 1
        touch -- "$touch_name"
        make clean # just in case
    else
        echo "Already used meson $(basename $cur_dir2)"
    fi
}

generic_meson() {
    local extra_configure_options="$1"
    mkdir -pv build
    do_meson "--prefix=${mingw_w64_x86_64_prefix} --libdir=${mingw_w64_x86_64_prefix}/lib --buildtype=release --default-library=static --cross-file=${top_dir}/meson-cross.mingw.txt $extra_configure_options . build"
}

generic_meson_ninja_install() {
    generic_meson "$1"
    do_ninja_and_ninja_install
}

do_ninja_and_ninja_install() {
    local extra_ninja_options="$1"
    do_ninja "$extra_ninja_options"
    local touch_name=$(get_small_touchfile_name already_ran_make_install "$extra_ninja_options")
    if [ ! -f $touch_name ]; then
        echo "ninja installing $(pwd) as $PATH=$PATH ninja -C build install $extra_make_options"
        ninja -C build install || exit 1
        touch $touch_name || exit 1
    fi
}

do_ninja() {
  local extra_make_options=" -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "${extra_make_options}")

  if [ ! -f $touch_name ]; then
    echo
    echo "ninja-ing $cur_dir2 as $ PATH=$PATH ninja -C build "${extra_make_options}"
    echo
    ninja -C build "${extra_make_options} || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already did ninja $(basename "$cur_dir2")"
  fi
}

apply_patch() {
  local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
  local patch_type=$2
  if [[ -z $patch_type ]]; then
    patch_type="-p0" # some are -p1 unfortunately, git's default
  fi
  local patch_name=$(basename $url)
  local patch_done_name="$patch_name.done"
  if [[ ! -e $patch_done_name ]]; then
    if [[ -f $patch_name ]]; then
      rm $patch_name || exit 1 # remove old version in case it has been since updated on the server...
    fi
    curl -4 --retry 5 $url -O --fail || echo_and_exit "unable to download patch file $url"
    echo "applying patch $patch_name"
    patch $patch_type < "$patch_name" || exit 1
    touch $patch_done_name || exit 1
    # too crazy, you can't do do_configure then apply a patch?
    # rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
  #else
  #  echo "patch $patch_name already applied" # too chatty
  fi
}

echo_and_exit() {
  echo "failure, exiting: $1"
  exit 1
}

# takes a url, output_dir as params, output_dir optional
download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [[ -z $output_dir ]]; then
    output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
  fi
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url" # redownload in case failed...
    if [[ -f $output_name ]]; then
      rm $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
    #  -L means "allow redirection" or some odd :|

    curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
    echo "unzipping $output_name ..."
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    rm "$output_name" || exit 1
  fi
}

generic_configure() {
  local extra_configure_options="$1"
  do_configure "--host=$host_target --prefix=$mingw_w64_x86_64_prefix --disable-shared --enable-static $extra_configure_options"
}

# params: url, optional "english name it will unpack to"
generic_download_and_make_and_install() {
  local url="$1"
  local english_name="$2"
  if [[ -z $english_name ]]; then
    english_name=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx, take last part of url
  fi
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "unable to cd, may need to specify dir it will unpack to as parameter"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  cd ..
}

do_git_checkout_and_make_install() {
  local url=$1
  local git_checkout_name=$(basename $url | sed s/\.git/_git/) # http://y/abc.git -> abc_git
  do_git_checkout $url $git_checkout_name
  cd $git_checkout_name
    generic_configure_make_install
  cd ..
}

generic_configure_make_install() {
  if [ $# -gt 0 ]; then
    echo "cant pass parameters to this method today, they'd be a bit ambiguous"
    echo "The following arguments where passed: ${@}"
    exit 1
  fi
  generic_configure # no parameters, force myself to break it up if needed
  do_make_and_make_install
}

gen_ld_script() {
  lib=$mingw_w64_x86_64_prefix/lib/$1
  lib_s="$2"
  if [[ ! -f $mingw_w64_x86_64_prefix/lib/lib$lib_s.a ]]; then
    echo "Generating linker script $lib: $2 $3"
    mv -f $lib $mingw_w64_x86_64_prefix/lib/lib$lib_s.a
    echo "GROUP ( -l$lib_s $3 )" > $lib
  fi
}

build_mingw_std_threads() {
  do_git_checkout https://github.com/meganz/mingw-std-threads.git # it needs std::mutex too :|
  cd mingw-std-threads_git
    cp *.h "$mingw_w64_x86_64_prefix/include"
  cd ..
}

build_zlib() {
  download_and_unpack_file https://github.com/madler/zlib/archive/v1.2.11.tar.gz zlib-1.2.11
  cd zlib-1.2.11
    local make_options
    if [[ $compiler_flavors == "native" ]]; then
      export CFLAGS="$CFLAGS -fPIC" # For some reason glib needs this even though we build a static library
    else
      export ARFLAGS=rcs # Native can't take ARFLAGS; https://stackoverflow.com/questions/21396988/zlib-build-not-configuring-properly-with-cross-compiler-ignores-ar
    fi
    do_configure "--prefix=$mingw_w64_x86_64_prefix --static"
    do_make_and_make_install "$make_prefix_options ARFLAGS=rcs"
    if [[ $compiler_flavors == "native" ]]; then
      reset_cflags
    else
      unset ARFLAGS
    fi
  cd ..
}

build_amd_amf_headers() {
  # was https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git too big
  # or https://github.com/DeadSix27/AMF smaller
  # but even smaller!
  do_git_checkout https://github.com/rdp/amf_headers.git amf_headers_git

  cd amf_headers_git
    if [ ! -f "already_installed" ]; then
      #rm -rf "./Thirdparty" # ?? plus too chatty...
      if [ ! -d "$mingw_w64_x86_64_prefix/include/AMF" ]; then
        mkdir -p "$mingw_w64_x86_64_prefix/include/AMF"
      fi
      cp -av "amf/public/include/." "$mingw_w64_x86_64_prefix/include/AMF"
      touch "already_installed"
    fi
  cd ..
}

build_nv_headers() {
  do_git_checkout https://github.com/FFmpeg/nv-codec-headers.git
  cd nv-codec-headers_git
    do_make_install "PREFIX=$mingw_w64_x86_64_prefix" # just copies in headers
  cd ..
}

build_ffmpeg() {
  local extra_postpend_configure_options=$2
  local build_type=$1
  if [[ -z $3 ]]; then
    local output_dir="ffmpeg_git"
  else
    local output_dir=$3
  fi
  if [[ "$non_free" = "y" ]]; then
    output_dir+="_with_fdk_aac"
  fi
  if [[ $build_intel_qsv == "n" ]]; then
    output_dir+="_xp_compat"
  fi
  if [[ $enable_gpl == 'n' ]]; then
    output_dir+="_lgpl"
  fi

  if [[ ! -z $ffmpeg_git_checkout_version ]]; then
    local output_branch_sanitized=$(echo ${ffmpeg_git_checkout_version} | sed "s/\//_/g") # release/4.3 to release_4.3
    output_dir+="_$output_branch_sanitized"
  else
    # If version not provided, assume master branch desired
    ffmpeg_git_checkout_version="master"
  fi

  local postpend_configure_opts=""
  local install_prefix=""
  # can't mix and match --enable-static --enable-shared unfortunately, or the final executable seems to just use shared if the're both present
  if [[ $build_type == "shared" ]]; then
    output_dir+="_shared"
    install_prefix="$(pwd)/${output_dir}" # install them to their a separate dir
  else
    install_prefix="${mingw_w64_x86_64_prefix}" # don't really care since we just pluck ffmpeg.exe out of the src dir for static, but x264 pre wants it installed...
  fi

  # allow using local source directory version of ffmpeg
  if [[ -z $ffmpeg_source_dir ]]; then
    do_git_checkout $ffmpeg_git_checkout $output_dir $ffmpeg_git_checkout_version || exit 1
  else
    output_dir="${ffmpeg_source_dir}"
    install_prefix="${output_dir}"
  fi

  if [[ $build_type == "shared" ]]; then
    postpend_configure_opts="--enable-shared --disable-static --prefix=${install_prefix}" # I guess this doesn't have to be at the end...
  else
    postpend_configure_opts="--enable-static --disable-shared --prefix=${install_prefix}"
  fi

  if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
    postpend_configure_opts="${postpend_configure_opts} --disable-libdav1d " # dav1d has diverged since so isn't compat with older ffmpegs
  fi

  cd $output_dir
    apply_patch file://$patch_dir/frei0r_load-shared-libraries-dynamically.diff
    if [ "$bits_target" = "32" ]; then
      local arch=x86
    else
      local arch=x86_64
    fi

    init_options="--pkg-config=pkg-config --pkg-config-flags=--static --extra-version=ffmpeg-windows-build-helpers --enable-version3 --disable-debug --disable-w32threads"
    if [[ $compiler_flavors != "native" ]]; then
      init_options+=" --arch=$arch --target-os=mingw32 --cross-prefix=$cross_prefix"
    else
      if [[ $OSTYPE != darwin* ]]; then
        unset PKG_CONFIG_LIBDIR # just use locally packages for all the xcb stuff for now, you need to install them locally first...
        init_options+=" --enable-libv4l2 --enable-libxcb --enable-libxcb-shm --enable-libxcb-xfixes --enable-libxcb-shape "
      fi
    fi
    if [[ `uname` =~ "5.1" ]]; then
      init_options+=" --disable-schannel"
      # Fix WinXP incompatibility by disabling Microsoft's Secure Channel, because Windows XP doesn't support TLS 1.1 and 1.2, but with GnuTLS or OpenSSL it does.  XP compat!
    fi
    config_options="$init_options --enable-libcaca --enable-gray --enable-libtesseract --enable-fontconfig --enable-gmp --enable-gnutls --enable-libass --enable-libbluray --enable-libbs2b --enable-libflite --enable-libfreetype --enable-libfribidi --enable-libgme --enable-libgsm --enable-libilbc --enable-libmodplug --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopus --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libtheora --enable-libtwolame --enable-libvo-amrwbenc --enable-libvorbis --enable-libwebp --enable-libzimg --enable-libzvbi --enable-libmysofa --enable-libopenjpeg  --enable-libopenh264  --enable-libvmaf --enable-libsrt --enable-libxml2 --enable-opengl --enable-libdav1d --enable-cuda-llvm"

    if [[ $build_svt = y ]]; then
      if [ "$bits_target" != "32" ]; then

        # SVT-VP9 see comments below
        # git apply "$work_dir/SVT-VP9_git/ffmpeg_plugin/master-0001-Add-ability-for-ffmpeg-to-run-svt-vp9.patch"

        # SVT-HEVC
        # Apply the correct patches based on version. Logic (n4.4 patch for n4.2, n4.3 and n4.4)  based on patch notes here:
        # https://github.com/OpenVisualCloud/SVT-HEVC/commit/b5587b09f44bcae70676f14d3bc482e27f07b773#diff-2b35e92117ba43f8397c2036658784ba2059df128c9b8a2625d42bc527dffea1
        if [[ $ffmpeg_git_checkout_version == *"n4.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.3"* ]] || [[ $ffmpeg_git_checkout_version == *"n4.2"* ]]; then
          git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/n4.4-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
          git apply "$patch_dir/SVT-HEVC-0002-doc-Add-libsvt_hevc-encoder-docs.patch"  # upstream patch does not apply on current ffmpeg master
        elif [[ $ffmpeg_git_checkout_version == *"n4.1"* ]] || [[ $ffmpeg_git_checkout_version == *"n3.4"* ]] || [[ $ffmpeg_git_checkout_version == *"n3.2"* ]] || [[ $ffmpeg_git_checkout_version == *"n2.8"* ]]; then
          : # too old...
        else
          git apply "$work_dir/SVT-HEVC_git/ffmpeg_plugin/master-0001-lavc-svt_hevc-add-libsvt-hevc-encoder-wrapper.patch"
        fi
        config_options+=" --enable-libsvthevc"
        config_options+=" --enable-libsvtav1"
        # config_options+=" --enable-libsvtvp9"
        #aom must be disabled to use SVT-AV1, just below
        #config_options+=" --enable-libsvtav1" #not currently working but compiles if configured

        #config_options+=" --enable-libvpx"
        #config_options+=" --enable-libsvtvp9" #not currently working but compiles if configured
      fi # else doesn't work/matter with 32 bit
    fi
    config_options+=" --enable-libaom"

    if [[ $compiler_flavors != "native" ]]; then
      config_options+=" --enable-nvenc --enable-nvdec" # don't work OS X
    fi

    config_options+=" --extra-libs=-lharfbuzz" #  grr...needed for pre x264 build???
    config_options+=" --extra-libs=-lm" # libflite seemed to need this linux native...and have no .pc file huh?
    config_options+=" --extra-libs=-lshlwapi" # lame needed this, no .pc file?
    config_options+=" --extra-libs=-lmpg123" # ditto
    config_options+=" --extra-libs=-lpthread" # for some reason various and sundry needed this linux native

    config_options+=" --extra-cflags=-DLIBTWOLAME_STATIC --extra-cflags=-DMODPLUG_STATIC --extra-cflags=-DCACA_STATIC" # if we ever do a git pull then it nukes changes, which overrides manual changes to configure, so just use these for now :|
    if [[ $build_amd_amf = n ]]; then
      config_options+=" --disable-amf" # Since its autodetected we have to disable it if we do not want it. #unless we define no autodetection but.. we don't.
    else
      config_options+=" --enable-amf" # This is actually autodetected but for consistency.. we might as well set it.
    fi

    if [[ $build_intel_qsv = y && $compiler_flavors != "native" ]]; then # Broken for native builds right now: https://github.com/lu-zero/mfx_dispatch/issues/71
      config_options+=" --enable-libmfx"
    else
      config_options+=" --disable-libmfx"
    fi
    if [[ $enable_gpl == 'y' ]]; then
      config_options+=" --enable-gpl --enable-frei0r --enable-librubberband --enable-libvidstab --enable-libx264 --enable-libx265 --enable-avisynth --enable-libaribb24"
      config_options+=" --enable-libxvid --enable-libdavs2"
      if [[ $host_target != 'i686-w64-mingw32' ]]; then
        config_options+=" --enable-libxavs2"
      fi
      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-libxavs" # don't compile OS X
      fi
    fi
    local licensed_gpl=n # lgpl build with libx264 included for those with "commercial" license :)
    if [[ $licensed_gpl == 'y' ]]; then
      apply_patch file://$patch_dir/x264_non_gpl.diff -p1
      config_options+=" --enable-libx264"
    fi
    # other possibilities:
    #   --enable-w32threads # [worse UDP than pthreads, so not using that]

    for i in $CFLAGS; do
      config_options+=" --extra-cflags=$i" # --extra-cflags may not be needed here, but adds it to the final console output which I like for debugging purposes
    done

    config_options+=" $postpend_configure_opts"

    if [[ "$non_free" = "y" ]]; then
      config_options+=" --enable-nonfree --enable-libfdk-aac"

      if [[ $compiler_flavors != "native" ]]; then
        config_options+=" --enable-decklink" # Error finding rpc.h in native builds even if it's available
      fi
      # other possible options: --enable-openssl [unneeded since we already use gnutls]
    fi

    do_debug_build=n # if you need one for backtraces/examining segfaults using gdb.exe ... change this to y :) XXXX make it affect x264 too...and make it real param :)
    if [[ "$do_debug_build" = "y" ]]; then
      # not sure how many of these are actually needed/useful...possibly none LOL
      config_options+=" --disable-optimizations --extra-cflags=-Og --extra-cflags=-fno-omit-frame-pointer --enable-debug=3 --extra-cflags=-fno-inline $postpend_configure_opts"
      # this one kills gdb workability for static build? ai ai [?] XXXX
      config_options+=" --disable-libgme"
    fi
    config_options+=" $extra_postpend_configure_options"

    config_options2="--pkg-config=pkg-config"
    config_options2+=" --disable-everything"
    config_options2+=" --pkg-config-flags=--static"
    config_options2+=" --extra-version=ffmpeg-windows-build-helpers"
    config_options2+=" --enable-version3"
    config_options2+=" --disable-debug"
    config_options2+=" --disable-w32threads"
    config_options2+=" --arch=x86_64"
    config_options2+=" --target-os=mingw32"
    config_options2+=" --cross-prefix=/ffmpeg-windows-build-helpers/sandbox/cross_compilers/mingw-w64-x86_64/bin/x86_64-w64-mingw32-"
    config_options2+=" --enable-nvenc"
    config_options2+=" --enable-nvdec"
    config_options2+=" --enable-amf"
    config_options2+=" --extra-cflags=-mtune=generic"
    config_options2+=" --extra-cflags=-O3"
    config_options2+=" --enable-static"
    config_options2+=" --disable-shared"
    config_options2+=" --prefix=/ffmpeg-windows-build-helpers/sandbox/cross_compilers/mingw-w64-x86_64/x86_64-w64-mingw32"
    config_options2+=" --enable-encoder=h264_nvenc"
    config_options2+=" --enable-encoder=h264_amf"
    config_options2+=" --enable-encoder=gif"
    config_options2+=" --enable-decoder=gif"
    config_options2+=" --enable-decoder=mjpeg"
    config_options2+=" --enable-encoder=mjpeg"
    config_options2+=" --enable-encoder=rawvideo"
    config_options2+=" --enable-decoder=rawvideo"
    config_options2+=" --enable-muxer=rawvideo"
    config_options2+=" --enable-demuxer=rawvideo"
    config_options2+=" --enable-muxer=mp4"
    config_options2+=" --enable-muxer=mjpeg"
    config_options2+=" --enable-muxer=gif"
    config_options2+=" --enable-demuxer=mjpeg"
    config_options2+=" --enable-demuxer=image2"
    config_options2+=" --enable-demuxer=gif"
    config_options2+=" --enable-protocol=file"
    config_options2+=" --enable-filter=scale"
    config_options2+=" --enable-filter=fps"
    config_options2+=" --enable-filter=hwupload"
    config_options2+=" --enable-filter=palettegen"
    config_options2+=" --enable-filter=paletteuse"
    config_options2+=" --enable-filter=split"
    config_options2+=" --enable-filter=setpts"
    config_options2+=" --enable-hwaccels"

    echo "Config 1: $config_options"
    echo "Config 2: $config_options2"

    do_configure "$config_options2"
    rm -f */*.a */*.dll *.exe # just in case some dependency library has changed, force it to re-link even if the ffmpeg source hasn't changed...
    rm -f already_ran_make*
    echo "doing ffmpeg make $(pwd)"

    do_make_and_make_install # install ffmpeg as well (for shared, to separate out the .dll's, for things that depend on it like VLC, to create static libs)

    # build ismindex.exe, too, just for fun
    if [[ $build_ismindex == "y" ]]; then
      make tools/ismindex.exe || exit 1
    fi

    # XXX really ffmpeg should have set this up right but doesn't, patch FFmpeg itself instead...
    if [[ $1 == "static" ]]; then
      if [[ $build_intel_qsv = y  && $compiler_flavors != "native" ]]; then # Broken for native builds right now: https://github.com/lu-zero/mfx_dispatch/issues/71
        sed -i.bak 's/-lavutil -lm.*/-lavutil -lm -lmfx -lstdc++ -lpthread/' "$PKG_CONFIG_PATH/libavutil.pc"
      else
        sed -i.bak 's/-lavutil -lm.*/-lavutil -lm -lpthread/' "$PKG_CONFIG_PATH/libavutil.pc"
      fi
      sed -i.bak 's/-lswresample -lm.*/-lswresample -lm -lsoxr/' "$PKG_CONFIG_PATH/libswresample.pc" # XXX patch ffmpeg
    fi

    sed -i.bak 's/-lswresample -lm.*/-lswresample -lm -lsoxr/' "$PKG_CONFIG_PATH/libswresample.pc" # XXX patch ffmpeg

    if [[ $non_free == "y" ]]; then
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)/bin"
      else
        echo "Done! You will find $bits_target-bit $1 non-redistributable binaries in $(pwd)"
      fi
    else
      mkdir -p $cur_dir/redist
      archive="$cur_dir/redist/ffmpeg-$(git describe --tags --match N)-win$bits_target-$1"
      if [[ $original_cflags =~ "pentium3" ]]; then
        archive+="_legacy"
      fi
      if [[ $build_type == "shared" ]]; then
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)/bin"
        # Some manual package stuff because the install_root may be cluttered with static as well...
        # XXX this misses the docs and share?
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > bin/COPYING.GPLv3.txt # XXX we include this even if it's not a GPL build?
          cp -r include bin
          cd bin
            7z a -mx=9 $archive.7z include *.exe *.dll *.lib COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
          cd ..
        fi
      else
        echo "Done! You will find $bits_target-bit $1 binaries in $(pwd)"
        if [[ ! -f $archive.7z ]]; then
          sed "s/$/\r/" COPYING.GPLv3 > COPYING.GPLv3.txt
          7z a -mx=9 $archive.7z ffmpeg.exe ffplay.exe ffprobe.exe COPYING.GPLv3.txt && rm -f COPYING.GPLv3.txt
        fi
      fi
      echo "You will find redistributable archive .7z file in $cur_dir/redist"
    fi
    echo `date`

  if [[ -z $ffmpeg_source_dir ]]; then
    cd ..
  else
    cd "$work_dir"
  fi
}

find_all_build_exes() {
  local found=""
# NB that we're currently in the sandbox dir...
  for file in `find . -name ffmpeg.exe` `find . -name ffmpeg_g.exe` `find . -name ffplay.exe` `find . -name ffmpeg` `find . -name ffplay` `find . -name ffprobe` `find . -name MP4Box.exe` `find . -name mplayer.exe` `find . -name mencoder.exe` `find . -name avconv.exe` `find . -name avprobe.exe` `find . -name x264.exe` `find . -name writeavidmxf.exe` `find . -name writeaviddv50.exe` `find . -name rtmpdump.exe` `find . -name x265.exe` `find . -name ismindex.exe` `find . -name dvbtee.exe` `find . -name boxdumper.exe` `find . -name muxer.exe ` `find . -name remuxer.exe` `find . -name timelineeditor.exe` `find . -name lwcolor.auc` `find . -name lwdumper.auf` `find . -name lwinput.aui` `find . -name lwmuxer.auf` `find . -name vslsmashsource.dll`; do
    found="$found $(readlink -f $file)"
  done

  # bash recursive glob fails here again?
  for file in `find . -name vlc.exe | grep -- -`; do
    found="$found $(readlink -f $file)"
  done
  echo $found # pseudo return value...
}

build_ffmpeg_dependencies() {
  build_mingw_std_threads
  build_zlib # Zlib in FFmpeg is autodetected.
  build_amd_amf_headers
  build_nv_headers
 }

build_apps() {
  build_ffmpeg static
}

# set some parameters initial values
top_dir="$(pwd)"
cur_dir="$(pwd)/sandbox"
patch_dir="$(pwd)/patches"
cpu_count="$(grep -c processor /proc/cpuinfo 2>/dev/null)" # linux cpu count
if [ -z "$cpu_count" ]; then
  cpu_count=`sysctl -n hw.ncpu | tr -d '\n'` # OS X cpu count
  if [ -z "$cpu_count" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite
  fi
fi
original_cpu_count=$cpu_count # save it away for some that revert it temporarily

set_box_memory_size_bytes
if [[ $box_memory_size_bytes -lt 600000000 ]]; then
  echo "your box only has $box_memory_size_bytes, 512MB (only) boxes crash when building cross compiler gcc, please add some swap" # 1G worked OK however...
  exit 1
fi

if [[ $box_memory_size_bytes -gt 2000000000 ]]; then
  gcc_cpu_count=$cpu_count # they can handle it seemingly...
else
  echo "low RAM detected so using only one cpu for gcc compilation"
  gcc_cpu_count=1 # compatible low RAM...
fi

# variables with their defaults
build_ffmpeg_static=y
build_ffmpeg_shared=n
build_dvbtee=n
build_libmxf=n
build_mp4box=n
build_mplayer=n
build_vlc=n
build_lsw=n # To build x264 with L-Smash-Works.
build_dependencies=y
git_get_latest=y
prefer_stable=y # Only for x264 and x265.
build_intel_qsv=y # note: not windows xp friendly!
build_amd_amf=y
disable_nonfree=y # comment out to force user y/n selection
original_cflags='-mtune=generic -O3' # high compatible by default, see #219, some other good options are listed below, or you could use -march=native to target your local box:
original_cppflags='-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0' # Needed for mingw-w64 7 as FORTIFY_SOURCE is now partially implemented, but not actually working
# if you specify a march it needs to first so x264's configure will use it :| [ is that still the case ?]

#flags=$(cat /proc/cpuinfo | grep flags)
#if [[ $flags =~ "ssse3" ]]; then # See https://gcc.gnu.org/onlinedocs/gcc/x86-Options.html, https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html and https://stackoverflow.com/questions/19689014/gcc-difference-between-o3-and-os.
#  original_cflags='-march=core2 -O2'
#elif [[ $flags =~ "sse3" ]]; then
#  original_cflags='-march=prescott -O2'
#elif [[ $flags =~ "sse2" ]]; then
#  original_cflags='-march=pentium4 -O2'
#elif [[ $flags =~ "sse" ]]; then
#  original_cflags='-march=pentium3 -O2 -mfpmath=sse -msse'
#else
#  original_cflags='-mtune=generic -O2'
#fi
ffmpeg_git_checkout_version=
build_ismindex=n
enable_gpl=y
build_x264_with_libav=n # To build x264 with Libavformat.
ffmpeg_git_checkout="https://github.com/FFmpeg/FFmpeg.git"
ffmpeg_source_dir=
build_svt=n

# parse command line parameters, if any
while true; do
  case $1 in
    -h | --help ) echo "available option=default_value:
      --build-ffmpeg-static=y  (ffmpeg.exe, ffplay.exe and ffprobe.exe)
      --build-ffmpeg-shared=n  (ffmpeg.exe (with libavformat-x.dll, etc., ffplay.exe, ffprobe.exe and dll-files)
      --ffmpeg-git-checkout-version=[master] if you want to build a particular version of FFmpeg, ex: n3.1.1 or a specific git hash
      --ffmpeg-git-checkout=[https://github.com/FFmpeg/FFmpeg.git] if you want to clone FFmpeg from other repositories
      --ffmpeg-source-dir=[default empty] specifiy the directory of ffmpeg source code. When specified, git will not be used.
      --x265-git-checkout-version=[master] if you want to build a particular version of x265, ex: --x265-git-checkout-version=Release_3.2 or a specific git hash
      --fdk-aac-git-checkout-version= if you want to build a particular version of fdk-aac, ex: --fdk-aac-git-checkout-version=v2.0.1 or another tag
      --gcc-cpu-count=[number of cpu cores set it higher than 1 if you have multiple cores and > 1GB RAM, this speeds up initial cross compiler build. FFmpeg build uses number of cores no matter what]
      --disable-nonfree=y (set to n to include nonfree like libfdk-aac,decklink)
      --build-intel-qsv=y (set to y to include the [non windows xp compat.] qsv library and ffmpeg module. NB this not not hevc_qsv...
      --sandbox-ok=n [skip sandbox prompt if y]
      -d [meaning \"defaults\" skip all prompts, just build ffmpeg static with some reasonable defaults like no git updates]
      --build-libmxf=n [builds libMXF, libMXF++, writeavidmxfi.exe and writeaviddv50.exe from the BBC-Ingex project]
      --build-mp4box=n [builds MP4Box.exe from the gpac project]
      --build-mplayer=n [builds mplayer.exe and mencoder.exe]
      --build-vlc=n [builds a [rather bloated] vlc.exe]
      --build-lsw=n [builds L-Smash Works VapourSynth and AviUtl plugins]
      --build-ismindex=n [builds ffmpeg utility ismindex.exe]
      -a 'build all' builds ffmpeg, mplayer, vlc, etc. with all fixings turned on [many disabled from disuse these days]
      --build-svt=n [builds libsvt-hevc modules within ffmpeg etc.]
      --build-dvbtee=n [build dvbtee.exe a DVB profiler]
      --compiler-flavors=[multi,win32,win64,native] [default prompt, or skip if you already have one built, multi is both win32 and win64]
      --cflags=[default is $original_cflags, which works on any cpu, see README for options]
      --git-get-latest=y [do a git pull for latest code from repositories like FFmpeg--can force a rebuild if changes are detected]
      --build-x264-with-libav=n build x264.exe with bundled/included "libav" ffmpeg libraries within it
      --prefer-stable=y build a few libraries from releases instead of git master
      --debug Make this script  print out each line as it executes
      --enable-gpl=[y] set to n to do an lgpl build
      --build-dependencies=y [builds the ffmpeg dependencies. Disable it when the dependencies was built once and can greatly reduce build time. ]
       "; exit 0 ;;
    --sandbox-ok=* ) sandbox_ok="${1#*=}"; shift ;;
    --gcc-cpu-count=* ) gcc_cpu_count="${1#*=}"; shift ;;
    --ffmpeg-git-checkout-version=* ) ffmpeg_git_checkout_version="${1#*=}"; shift ;;
    --ffmpeg-git-checkout=* ) ffmpeg_git_checkout="${1#*=}"; shift ;;
    --ffmpeg-source-dir=* ) ffmpeg_source_dir="${1#*=}"; shift ;;
    --x265-git-checkout-version=* ) x265_git_checkout_version="${1#*=}"; shift ;;
    --fdk-aac-git-checkout-version=* ) fdk_aac_git_checkout_version="${1#*=}"; shift ;;
    --build-libmxf=* ) build_libmxf="${1#*=}"; shift ;;
    --build-mp4box=* ) build_mp4box="${1#*=}"; shift ;;
    --build-ismindex=* ) build_ismindex="${1#*=}"; shift ;;
    --git-get-latest=* ) git_get_latest="${1#*=}"; shift ;;
    --build-amd-amf=* ) build_amd_amf="${1#*=}"; shift ;;
    --build-intel-qsv=* ) build_intel_qsv="${1#*=}"; shift ;;
    --build-x264-with-libav=* ) build_x264_with_libav="${1#*=}"; shift ;;
    --build-mplayer=* ) build_mplayer="${1#*=}"; shift ;;
    --cflags=* )
       original_cflags="${1#*=}"; echo "setting cflags as $original_cflags"; shift ;;
    --build-vlc=* ) build_vlc="${1#*=}"; shift ;;
    --build-lsw=* ) build_lsw="${1#*=}"; shift ;;
    --build-dvbtee=* ) build_dvbtee="${1#*=}"; shift ;;
    --disable-nonfree=* ) disable_nonfree="${1#*=}"; shift ;;
    # this doesn't actually "build all", like doesn't build 10 high-bit LGPL ffmpeg, but it does exercise the "non default" type build options...
    -a         ) compiler_flavors="multi"; build_mplayer=n; build_libmxf=y; build_mp4box=y; build_vlc=y; build_lsw=y;
                 build_ffmpeg_static=y; build_ffmpeg_shared=y; build_lws=y; disable_nonfree=n; git_get_latest=y;
                 sandbox_ok=y; build_amd_amf=y; build_intel_qsv=y; build_dvbtee=y; build_x264_with_libav=y; shift ;;
    --build-svt=* ) build_svt="${1#*=}"; shift ;;
    -d         ) gcc_cpu_count=$cpu_count; disable_nonfree="y"; sandbox_ok="y"; compiler_flavors="win64"; git_get_latest="n"; shift ;;
    --compiler-flavors=* )
         compiler_flavors="${1#*=}";
         if [[ $compiler_flavors == "native" && $OSTYPE == darwin* ]]; then
           build_intel_qsv=n
           echo "disabling qsv since os x"
         fi
         shift ;;
    --build-ffmpeg-static=* ) build_ffmpeg_static="${1#*=}"; shift ;;
    --build-ffmpeg-shared=* ) build_ffmpeg_shared="${1#*=}"; shift ;;
    --prefer-stable=* ) prefer_stable="${1#*=}"; shift ;;
    --enable-gpl=* ) enable_gpl="${1#*=}"; shift ;;
    --build-dependencies=* ) build_dependencies="${1#*=}"; shift ;;
    --debug ) set -x; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

reset_cflags # also overrides any "native" CFLAGS, which we may need if there are some 'linux only' settings in there
reset_cppflags # Ensure CPPFLAGS are cleared and set to what is configured
check_missing_packages # do this first since it's annoying to go through prompts then be rejected
intro # remember to always run the intro, since it adjust pwd
install_cross_compiler

export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]

if [[ $OSTYPE == darwin* ]]; then
  # mac add some helper scripts
  mkdir -p mac_helper_scripts
  cd mac_helper_scripts
    if [[ ! -x readlink ]]; then
      # make some scripts behave like linux...
      curl -4 file://$patch_dir/md5sum.mac --fail > md5sum  || exit 1
      chmod u+x ./md5sum
      curl -4 file://$patch_dir/readlink.mac --fail > readlink  || exit 1
      chmod u+x ./readlink
    fi
    export PATH=`pwd`:$PATH
  cd ..
fi

original_path="$PATH"

if [[ $compiler_flavors == "native" ]]; then
  echo "starting native build..."
  # realpath so if you run it from a different symlink path it doesn't rebuild the world...
  # mkdir required for realpath first time
  mkdir -p $cur_dir/cross_compilers/native
  mkdir -p $cur_dir/cross_compilers/native/bin
  mingw_w64_x86_64_prefix="$(realpath $cur_dir/cross_compilers/native)"
  mingw_bin_path="$(realpath $cur_dir/cross_compilers/native/bin)" # sdl needs somewhere to drop "binaries"??
  export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
  export PATH="$mingw_bin_path:$original_path"
  make_prefix_options="PREFIX=$mingw_w64_x86_64_prefix"
  if [[ $(uname -m) =~ 'i686' ]]; then
    bits_target=32
  else
    bits_target=64
  fi
  #  bs2b doesn't use pkg-config, sndfile needed Carbon :|
  export CPATH=$cur_dir/cross_compilers/native/include:/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Headers # C_INCLUDE_PATH
  export LIBRARY_PATH=$cur_dir/cross_compilers/native/lib
  work_dir="$(realpath $cur_dir/native)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_ffmpeg
  cd ..
fi

if [[ $compiler_flavors == "multi" || $compiler_flavors == "win32" ]]; then
  echo
  echo "Starting 32-bit builds..."
  host_target='i686-w64-mingw32'
  mkdir -p $cur_dir/cross_compilers/mingw-w64-i686/$host_target
  mingw_w64_x86_64_prefix="$(realpath $cur_dir/cross_compilers/mingw-w64-i686/$host_target)"
  mkdir -p $cur_dir/cross_compilers/mingw-w64-i686/bin
  mingw_bin_path="$(realpath $cur_dir/cross_compilers/mingw-w64-i686/bin)"
  export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
  export PATH="$mingw_bin_path:$original_path"
  bits_target=32
  cross_prefix="$mingw_bin_path/i686-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
  work_dir="$(realpath $cur_dir/win32)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_apps
  cd ..
fi

if [[ $compiler_flavors == "multi" || $compiler_flavors == "win64" ]]; then
  echo
  echo "**************Starting 64-bit builds..." # make it have a bit easier to you can see when 32 bit is done
  host_target='x86_64-w64-mingw32'
  mkdir -p $cur_dir/cross_compilers/mingw-w64-x86_64/$host_target
  mingw_w64_x86_64_prefix="$(realpath $cur_dir/cross_compilers/mingw-w64-x86_64/$host_target)"
  mkdir -p $cur_dir/cross_compilers/mingw-w64-x86_64/bin
  mingw_bin_path="$(realpath $cur_dir/cross_compilers/mingw-w64-x86_64/bin)"
  export PKG_CONFIG_PATH="$mingw_w64_x86_64_prefix/lib/pkgconfig"
  export PATH="$mingw_bin_path:$original_path"
  bits_target=64
  cross_prefix="$mingw_bin_path/x86_64-w64-mingw32-"
  make_prefix_options="CC=${cross_prefix}gcc AR=${cross_prefix}ar PREFIX=$mingw_w64_x86_64_prefix RANLIB=${cross_prefix}ranlib LD=${cross_prefix}ld STRIP=${cross_prefix}strip CXX=${cross_prefix}g++"
  work_dir="$(realpath $cur_dir/win64)"
  mkdir -p "$work_dir"
  cd "$work_dir"
    build_ffmpeg_dependencies
    build_apps
  cd ..
fi

echo "searching for all local exe's (some may not have been built this round, NB)..."
for file in $(find_all_build_exes); do
  echo "built $file"
done
