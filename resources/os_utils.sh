# From https://github.com/DavidBakerEffendi/tigergraph/blob/master/3/3.0.5/resources/os_utils
# Essentially, this overwrites the default os_utils in the container in order to ensure that the low-resource
# runners used by a CI/CD platform wouldn't fail TigerGraph's extremely strict resource requirements
# See: https://docs-beta.tigergraph.com/admin/admin-guide/hw-and-sw-requirements

#!/bin/bash
#
# OS related utils: os detect, os check
# dependency check, disk space check
#

get_os(){
  if [ -f "/etc/apt/sources.list" ]; then
    if [ -f "/etc/linx-release" ]; then
      # [GF-773] support Rocky OS 6.0.80+
      os_version=$(cat /etc/linx-release | grep -o '[0-9]\.[0-9]\.[0-9]\{1,3\}' )
      echo "ROCKY $os_version"
    elif [ -f "/etc/lsb-release" ]; then
      os_version=$(cat /etc/lsb-release | grep  "DISTRIB_RELEASE" | cut -d= -f2)
      echo "UBUNTU $os_version"
    elif [ -f "/etc/os-release" ]; then
      os_version=$(cat /etc/os-release | grep  "VERSION_ID" | cut -d= -f2)
      os_version=${os_version//\"}  # remove all double quotes
      echo "DEBIAN $os_version"
    fi
  elif [ -d "/etc/yum.repos.d" ]; then
    # Centos and RedHat are treated equally
    # to deal with "Amazon Linux AMI release 2018.03"
    # another solution: grep -E "CentOS|Red Hat"
    if grep "Amazon Linux" /etc/system-release &>/dev/null; then
      # internally treat Amazon Linux as RHEL 7.0
      os_version=" 7.0"
    else
      # ER-255, RHEL 6.10
      os_version="$(cat /etc/system-release | grep -o ' [0-9]\.[0-9]\{1,3\}')"
    fi
    echo "RHEL$os_version"
  elif [ -d "/etc/zypp/repos.d" ]; then
    # [ER-241] support openSUSE 12
    os_version=$(cat /etc/os-release | grep  "VERSION_ID" | cut -d= -f2)
    os_version=${os_version//\"}  # remove all double quotes
    echo "SUSE $os_version"
  else
    echo "UNKOWN OS"
  fi
}

check_os(){
  OS=$1
  version=$2
  note "OS obtained: $OS $version"
  local error_msg="Unsupported OS. Current support CentOS 6.5 to 8.0; RedHat 6.5 to 8.0;
Ubuntu 14.04, 16.04, 18.04; Debian 8; SUSE 12; Amazon Linux 2016.03 to 2018.03; Rocky 6.0.80"
  if [ -z "$version" ]; then
     error "Unknown OS version. $error_msg"
     exit $E_UNSUPPORTOS
  fi
  if [ "$OS" = "UBUNTU" ]; then
    if [ "$version" != "14.04" -a "$version" != "16.04" -a "$version" != "18.04" ]; then
      error "$error_msg"
      exit $E_UNSUPPORTOS
    else
      note "OS check passed [OK]"
    fi
  elif [ "$OS" = "DEBIAN" ]; then
    if [ "$version" != "8" ]; then
      error "$error_msg"
      exit $E_UNSUPPORTOS
    else
      note "OS check passed [OK]"
    fi
  elif [ "$OS" = "RHEL" ]; then
    local ver_arr=(${version//./ })
    if [ "${ver_arr[0]}" -lt "6" ] || [ "${ver_arr[0]}" -eq "6" -a "${ver_arr[1]}" -lt "5" ]; then
      error "$error_msg"
      exit $E_UNSUPPORTOS
    else
      note "OS check passed [OK]"
    fi
  elif [ "$OS" = "SUSE" ]; then
    local ver_arr=(${version//./ })
    if [ "${ver_arr[0]}" -lt "12" ]; then
      error "$error_msg"
      exit $E_UNSUPPORTOS
    else
      note "OS check passed [OK]"
    fi
  elif [ "$OS" = "ROCKY" ]; then
    local ver_arr=(${version//./ })
    if [ "${ver_arr[0]}" -lt "6" ] || [ "${ver_arr[0]}" -eq "6" -a "${ver_arr[1]}" -eq "0" -a "${ver_arr[2]}" -lt "80" ]; then
      error "$error_msg"
      exit $E_UNSUPPORTOS
    else
      note "OS check passed [OK]"
    fi
  else
    error "$error_msg"
    exit $E_UNSUPPORTOS
  fi
}

check_preinstall_tools(){
  local OS=$1; shift
  declare -a tools=( "${@:2:$1}" ); shift "$(( $1 + 1 ))"
  declare -a pkg_tool=( "${@:2:$1}" ); shift "$(( $1 + 1 ))"

  if ! which "which" >/dev/null 2>&1; then
    # only Centos/HedHat need to install which, other OS contains 'which' by default
    error "Missing tool: which, please install it and retry."
    note "If you have internet access, you may install them by command: \"yum install which\""
    exit $E_MISSTOOL
  fi

  miss_tool=''
  pre_tool=''
  for i in "${!tools[@]}"; do
    tool="${tools[$i]}"
    if ! which $tool > /dev/null 2>&1; then
      if [ -z "$miss_tool" ]; then
        miss_tool="${pkg_tool[$i]}"
      else
        if [ "$pre_tool" != "${pkg_tool[$i]}" ]; then
          miss_tool="$miss_tool ${pkg_tool[$i]}"
        fi
      fi
      pre_tool="${pkg_tool[$i]}"
    fi
  done
  if [ ! -z "$miss_tool" ]; then
    error "Missing one or more tools: $miss_tool, please install these tools and retry."
    if [ "$OS" = "RHEL" ]; then
      note "If you have internet access, you may install them by command: \"yum install $miss_tool\""
    else
      note "If you have internet access, you may install them by command: \"apt-get install $miss_tool\""
    fi
    exit $E_MISSTOOL
  else
    note "Check prerequisite tools passed [OK]"
  fi
}

check_memory_capacity(){
  # [RFC-410] check if machine has enough memory
  # 8 GB = 8388608 kB
  # 7 GB = 7340032 kB
  # for Amazon ec2 m3.large only contains 7495280 kB
  # therefore set the min_kB a little bit larger than 7 GB
  warn "Memory minimum reduced to 2GB"
  local min_kB=2000000
  local size=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  let "size_GB = size / 1024 / 1024"
  let "min_GB = min_kB / 1024 / 1024"
  if [ "$min_GB" -lt 8 ]; then
    min_GB=8
  fi
  if [ "$size" -lt "$min_kB" ]; then
    warn "The machine does NOT have enough total memory (RAM): $size_GB GB, required at least $min_GB GB"
    return $E_LESSTHANLIMIT
  else
    note "Total memory (RAM): $size_GB GB [ok]"
  fi
}

check_cpu_number(){
  # [RFC-410] check if machine has enough CPU(s)
  warn "CPU minimum reduced to 1 core"
  local min_Num=1
  local num=$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)
  if [ "$num" -lt "$min_Num" ]; then
    warn "The machine does NOT have enough total CPU(s): $num, required at least $min_Num"
    return $E_LESSTHANLIMIT
  else
    note "Total CPU(s): $num [ok]"
  fi
}

check_root_space(){
  local GSQL_ROOT_DIR=$1
  # find the first exist directory of in path GSQL_ROOT_DIR
  local f=$GSQL_ROOT_DIR
  while [[ $f != "/" ]]; do
    if [ -d "$f" ]; then
      break
    else
      f=$(dirname $f)
    fi
  done
  size=$(df -Pk $f | tail -1 | awk '{print $4}')
  let "size_GB = size / 1024 / 1024"
  minimum=20
  if [ $size_GB -lt $minimum ]; then
    warn "TigerGraph.Root.Dir: $GSQL_ROOT_DIR does NOT have enough available disk space: $size_GB GB, required at least $minimum GB"
    return $E_DISKNOTENOUGH
  else
    note "Available disk space: $size_GB GB [ok]"
  fi
}

check_home_space(){
  # move ~/.syspre ~/.gium ~/.gsql* to root dir, and create symbolic links
  local GSQL_HOME=$1
  size=$(df -Pk $GSQL_HOME | tail -1 | awk '{print $4}')
  let "size_MB = size / 1024"
  minimum=200
  if [ $size_MB -lt $minimum ]; then
    error "TigerGraph User Home: $GSQL_HOME does NOT have enough available disk space: $size_MB MB, required at least $minimum MB"
    return $E_DISKNOTENOUGH
  else
    note "Available disk space: $size_MB MB [ok]"
  fi
}

check_preq_pkgs(){
  local OS=$1; shift
  declare -a tools=( "${@:2:$1}" ); shift "$(( $1 + 1 ))"
  declare -a pkg_tool=( "${@:2:$1}" ); shift "$(( $1 + 1 ))"

  # sbin path is not included in Deiban OS
  export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
  if ! which "which" >/dev/null 2>&1; then
    error "Missing tool: which, please install it and retry."
    note "If you have internet access, you may install them by command: yum install which"
    exit $E_MISSTOOL
  fi

  miss_tool=''
  pre_tool=''
  for i in "${!tools[@]}"; do
    tool="${tools[$i]}"
    if ! which $tool > /dev/null 2>&1; then
      if [ "$tool" = "iptables-persistent" ]; then
        if [ "$OS" = "RHEL" ]; then
          continue
        elif dpkg -S $tool &>/dev/null; then
          # ubuntu or debian must install iptables-persistent to make rules permanent
          continue
        elif rpm -q "iptables" &>/dev/null; then
          # suse check if iptables installed
          continue
        fi
      fi
      if [ -z "$miss_tool" ]; then
        miss_tool="${pkg_tool[$i]}"
      else
        if [ "$pre_tool" != "${pkg_tool[$i]}" ]; then
          miss_tool="$miss_tool ${pkg_tool[$i]}"
        fi
      fi
      pre_tool="${pkg_tool[$i]}"
    fi
  done
  if [ ! -z "$miss_tool" ]; then
    error "Missing one or more tools: $miss_tool, please install these tools and retry."
    if [ "$OS" = "RHEL" ]; then
      note "If you have internet access, you may install them by command: \"yum install $miss_tool\""
    elif [ "$OS" = "SUSE" ]; then
      note "If you have internet access, you may install them by command: \"zypper install $miss_tool\""
    else
      note "If you have internet access, you may install them by command: \"apt-get install $miss_tool\""
    fi
    # the file is on remote node: /tmp/tigergraph_utils/utils/miss_tools
    echo "$NODE_NAME:$OS:$miss_tool" > $BASE_DIR/utils/miss_tools
    mesg_cyan "or run \"./install_tools.sh\", it will install all missing tools on related nodes."
    exit $E_MISSTOOL
  else
    note "Check prerequisite tools passed [OK]"
  fi
}

set_user(){
  GSQL_USER=$1
  GSQL_USER_PWD=$2
  # set user is independent with set root
  if id ${GSQL_USER} >/dev/null 2>&1; then
    note "Installing platform under the existing user: ${GSQL_USER}"
    GSQL_USER_HOME=$(eval echo ~$GSQL_USER)
    if ! [ -d "$GSQL_USER_HOME" ]; then
      error "TigerGraph user ($GSQL_USER) exists, but its home directory does not exist."
      note "Please create the home directory of $GSQL_USER, and retry."
      exit $E_FILENOTFOUND
    fi
    echo "${GSQL_USER}:${GSQL_USER_PWD}" | chpasswd &>/dev/null
  else
    prog "Creating new user: ${GSQL_USER}"
    # always set GSQL_USER_HOME=/home/$GSQL_USER for new user
    # this will enable ssh, and no need to check HOME space
    # mv ~/.syspre, ~/.gium, ~/.gsql* to $GSQL_ROOT_DIR, and create symbolic links
    home_path="/home/$GSQL_USER"
    note "User (${GSQL_USER}) home directory is: $home_path"
    # the directory $home_path may already exist
    useradd ${GSQL_USER} -U -m -d $home_path -c "TigerGraph User" -s /bin/bash &>/dev/null
    check_fail $? $E_CREATEUSERFAIL "${bldred}Failed to create user ${GSQL_USER}. Program terminated. $txtrst"
    echo "${GSQL_USER}:${GSQL_USER_PWD}" | chpasswd &>/dev/null
  fi
  GSQL_USER_HOME=$(eval echo ~$GSQL_USER)
  # don't use '-R', if HOME is large, -R will take very long time
  chown $GSQL_USER $GSQL_USER_HOME
  # make sure the realpath belongs to GSQL_USER if GSQL_USER_HOME is a symbolic link
  chown $GSQL_USER $(cd $GSQL_USER_HOME && pwd -P)
}

set_root(){
  mkdir -p $GSQL_ROOT_DIR
  check_fail $? $E_CREATEPATHFAIL "${bldred}Failed to creat install directory: ${GSQL_ROOT_DIR}. Program terminated. $txtrst"
  local fs_type=$(df -PT $GSQL_ROOT_DIR | tail -1 | awk '{print $2}')
  if [ "$fs_type" = "tmpfs" ]; then
    error "TigerGraph.Root.Dir installation directory ($GSQL_ROOT_DIR) cannot be 'tmpfs' filesystem type."
    note "Please specfiy a non tmpfs type TigerGraph.Root.Dir installation path, and retry."
    exit $E_CREATEPATHFAIL
  fi
  # set +rx permissions to GSQL_ROOT_DIR directory and all its parent directores
  # start from the GSQL_ROOT_DIR, and works on every parent dir, until it encounters '/'
  # Does not chmod '/'
  local f=$GSQL_ROOT_DIR
  while [[ $f != "/" ]]; do chmod a+rx $f; f=$(dirname $f); done;
  # user GSQL_USER may not exist
  # need to do one more time after set_user
  chown -R $GSQL_USER $GSQL_ROOT_DIR &>/dev/null
}

create_root(){
  echo -n "${bldgre}The tigergraph platform install directory: $GSQL_ROOT_DIR does NOT have enough space. Change this? (y/N): $txtrst"
  read change
  if [ "$change" = "y" -o "$change" = "Y" ]; then
    new_root=''
    while [ -z "$new_root" ]; do
      echo -n "${bldgre}Please enter the new tigergraph platform install directory path:  $txtrst"
      read new_root < /dev/tty
      echo
      if [ -z "$new_root" ]; then
        warn "No path supplied"
      elif [ "$new_root" = '/' ]; then
        warn "Input path cannot be '/'"
        new_pwd=''
      elif [[ "$new_root" =~ [$' \t'] ]]; then
        # match any space, tab character
        warn "Input path contains space or tab character"
        new_pwd=''
      fi
    done
    GSQL_ROOT_DIR=$new_root
  else
    echo "${bldred}Abort by user $txtrst"
    exit $E_DISKNOTENOUGH
  fi

  # Normalize the path, eliminate duplicate slashes '/'
  normalize_root_dir

  check_root_space $GSQL_ROOT_DIR
  if [ "$?" != 0 ]; then
    warn "The new path: $GSQL_ROOT_DIR still does NOT have enough disk space, installation terminated"
    exit $E_DISKNOTENOUGH
  fi

  # set the new root directory
  set_root
}

move_home(){
  local OLD_HOME="$GSQL_USER_HOME"
  GSQL_USER_HOME="$(cd $GSQL_ROOT_DIR/.. && pwd)/tigergraph_home"
  mkdir -p $GSQL_USER_HOME
  note "Changing TigerGraph User Home to be: $GSQL_USER_HOME"

  size_root=$(df -Pk $GSQL_ROOT_DIR | tail -1 | awk '{print $4}')
  let "size_root_GB = size_root / 1024 / 1024"
  size_root_remain=$((size_root_GB - 20))
  size_home=$(df -Pk $OLD_HOME | tail -1 | awk '{print $4}')
  let "size_home_GB = size_home / 1024 / 1024"
  if [ $size_root_remain -lt $size_home_GB ]; then
    warn "Cannot move TigerGraph User Home from $OLD_HOME to $GSQL_USER_HOME due to insufficient disk space."
    mesg_red "Installation terminated."
    exit $E_DISKNOTENOUGH
  fi
  # copy everything from old home to new home
  # don't use move because if move failed, then part of the files in old home will be lost
  # cannot use "cp -r $OLD_HOME/* $GSQL_USER_HOME/", it only include non-hidden files
  # cannot use "cp -r $OLD_HOME/.* $GSQL_USER_HOME/", it will include ".", ".."
  if [ -d $OLD_HOME ]; then
    for item in $(ls -a $OLD_HOME); do
      if [ $item = "." -o $item = ".." ]; then
        # ignore this two folder
        continue
      fi
      cp -rfp $OLD_HOME/$item $GSQL_USER_HOME/
      check_fail $? $E_DISKNOTENOUGH "${bldred}Failed to copy files/dir $OLD_HOME/$item to $GSQL_USER_HOME, \
          please check if resource busy or other reasons. $txtrst"
    done
  fi

  chown -R $GSQL_USER $GSQL_USER_HOME

  if [ "$OLD_HOME" != "/" ]; then
    mv $OLD_HOME ${OLD_HOME}_backup
    ln -sf $GSQL_USER_HOME $OLD_HOME
    check_fail $? $E_RESOURCEBUSY "${bldred}Failed to create symbolic link: ln -sf $GSQL_USER_HOME $OLD_HOME,  \
        please create the link and retry $txtrst"
    rm -rf ${OLD_HOME}_backup || :
    chown -R $GSQL_USER $OLD_HOME
  else
    warn "Old tigergraph user home is '/', cannot create symbolic link"
    exit $E_LINKFAIL
  fi
}