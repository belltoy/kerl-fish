#! /bin/fish

# set CMDNAME (basename (status --current-filename))
set ERLANG_DOWNLOAD_URL "http://www.erlang.org/download"

set KERL_BASE_DIR "$HOME/.kerl"
set KERL_CONFIG "$HOME/.kerlrc"
set KERL_DOWNLOAD_DIR "$KERL_BASE_DIR/archives"
set KERL_BUILD_DIR "$KERL_BASE_DIR/builds"
set KERL_GIT_DIR "$KERL_BASE_DIR/gits"

if test -n "$KERL_CONFIGURE_OPTIONS"
    set _KCO "$KERL_CONFIGURE_OPTIONS"
end
if test -n "$KERL_CONFIGURE_APPLICATIONS"
    set _KCA "$KERL_CONFIGURE_APPLICATIONS"
end
if test -n "$KERL_CONFIGURE_DISABLE_APPLICATIONS"
    set _KCDA "$KERL_CONFIGURE_DISABLE_APPLICATIONS"
end
if test -n "$KERL_SASL_STARTUP"
    set _KSS "$KERL_SASL_STARTUP"
end
if test -n "$KERL_DEPLOY_SSH_OPTIONS"
    set _KDSSH "$KERL_DEPLOY_SSH_OPTIONS"
end
if test -n "$KERL_DEPLOY_RSYNC_OPTIONS"
    set _KDRSYNC "$KERL_DEPLOY_RSYNC_OPTIONS"
end
if test -n "KERL_INSTALL_MANPAGES"
    set _KIM "$KERL_INSTALL_MANPAGES"
end
set -e KERL_CONFIGURE_OPTIONS
set -e KERL_CONFIGURE_APPLICATIONS
set -e KERL_CONFIGURE_DISABLE_APPLICATIONS
set -e KERL_SASL_STARTUP
set -e KERL_INSTALL_MANPAGES

# ensure the base dir exsists
mkdir -p "$KERL_BASE_DIR"

# source the config file if available
if test -f "$KERL_CONFIG"
    . "$KERL_CONFIG"
end

if test -n "$_KCO"
    set KERL_CONFIGURE_OPTIONS "$_KCO"
end
if test -n "$_KCA"
    set KERL_CONFIGURE_APPLICATIONS "$_KCA"
end
if test -n "$_KCDA"
    set KERL_CONFIGURE_DISABLE_APPLICATIONS "$_KCDA"
end
if test -n "$_KSS"
    set KERL_SASL_STARTUP "$_KSS"
end
if test -n "$_KDSSH"
    set KERL_DEPLOY_SSH_OPTIONS "$_KDSSH"
end
if test -n "$_KDRSYNC"
    set KERL_DEPLOY_RSYNC_OPTIONS "$_KDRSYNC"
end
if test -n "$_KIM"
    set KERL_INSTALL_MANPAGES "$_KIM"
end

if test -z "$KERL_SASL_STARTUP"
    set INSTALL_OPT -minimal
else
    set INSTALL_OPT -sasl
end

set KERL_SYSTEM (uname -s)
switch $KERL_SYSTEM
    case Darwin FreeBSD OpenBSD
        set MD5SUM openssl md5
        set MD5SUM_FIELD 2
        set SED_OPT -E
    case '*'
        set MD5SUM md5sun
        set MD5SUM_FIELD 1
        set SED_OPT -r
end

function kerl_usage
    echo "kerl: build and install Erlang/OTP"
    echo "usage: kerl <command> [options ...]"
    echo ""
    echo "  <command>       Command to be executed"
    echo ""
    echo "Valid commands are:"
    echo "  build    Build specified release or git repository"
    echo "  install  Install the specified release at the given location"
    echo "  deploy   Deploy the specified installation to the given host and location"
    echo "  update   Update the list of available releases from erlang.org"
    echo "  list     List releases, builds and installations"
    echo "  delete   Delete builds and installations"
    echo "  active   Print the path of the active installation"
    echo "  status   Print available builds and installations"
    echo "  prompt   Print a string suitable for insertion in prompt"
    echo "  cleanup  Remove compilation artifacts (use after installation)"
    return 1
end

# if [ (count $argv) -eq 0 ]
#     kerl_usage
# end


# TODO
function kerl_get_releases
    curl -L -s $ERLANG_DOWNLOAD_URL/ | \
        sed $SED_OPT -e 's/^.*<[aA] [hH][rR][eE][fF]=\"\/download\/otp_src_([-0-9A-Za-z_.]+)\.tar\.gz\">.*$/\1/' \
                     -e '/^R1|^[0-9]/!d' | \
        sed -e 's/^R\(.*\)/\1:R\1/' | sed -e 's/^\([^\:]*\)$/\1-z:\1/' | sort | cut -d':' -f2
end

function kerl_update_checksum_file
    echo "Getting the checksum file from erlang.org..."
    curl -L $ERLANG_DOWNLOAD_URL/MD5 > "$KERL_DOWNLOAD_DIR/MD5" ;or return 1
end

function kerl_ensure_checksum_file
    if test ! -f "$KERL_DOWNLOAD_DIR/MD5"
        kerl_update_checksum_file
    end
end

function kerl_check_releases
    if test ! -f "$KERL_BASE_DIR/otp_releases"
        echo "Getting the available releases from erlang.org..."
        kerl_get_releases > "$KERL_BASE_DIR/otp_releases"
    end
end

set KERL_NO_LION_SUPPORT "R10B-0 R10B-2 R10B-3 R10B-4 R10B-5 R10B-6 R10B-7
R10B-8 R10B-9 R11B-0 R11B-1 R11B-2 R11B-3 R11B-4 R11B-5 R12B-0 R12B-1
R12B-2 R12B-3 R12B-4 R12B-5 R13A R13B R13B01 R13B02 R13B03 R13B04 R14A R14B R14B01 R14B02 R14B03"

function kerl_lion_support
    for v in $KERL_NO_LION_SUPPORT
        if test "$v" = $argv[1]
           return 1
        end
    end
    return 0
end

function kerl_is_valid_release
    kerl_check_releases
    for rel in (cat $KERL_BASE_DIR/otp_releases)
        if test $argv[1] = "$rel"
            return 0
        end
    end
    return 1
end

function kerl_assert_valid_release
    if test ! kerl_is_valid_release $argv[1]
        echo "$argv[1] is not a valid Erlang/OTP release"
        return 1
    end
    return 0
end

function kerl_get_release_from_name
    if test -f "$KERL_BASE_DIR/otp_builds"
        for l in (cat "$KERL_BASE_DIR/otp_builds")
            set -l rel (echo $l | cut -d "," -f 1)
            set -l name (echo $l | cut -d "," -f 2)
            if test "$name" = "$argv[1]"
                echo "$rel"
                return 0
            end
        end
    end
    return 1
end

function kerl_get_newest_valid_release
    kerl_check_releases
    for rel in (cat $KERL_BASE_DIR/otp_releases | tail -1)
        if test ! -z "$rel"
            echo "$rel"
            return 0
        end
    end
    return 1
end

function kerl_is_valid_installation
    if test -f "$argv[1]/activate"
        return 0
    end
    return 1
end

function kerl_assert_valid_installation
    if test ! kerl_is_valid_installation $argv[1]
        echo "$argv[1] is not a kerl-managed Erlang/OTP installation"
        return 1
    end
    return 0
end

function kerl_assert_build_name_unused
    if test -f "$KERL_BASE_DIR/otp_builds"
        for l in (cat "$KERL_BASE_DIR/otp_builds")
            set name (echo $l | cut -d "," -f 2)
            if test "$name" = "$argv[1]"
                echo "There's already a build named $argv[1]"
                return 1
            end
        end
    end
end

function kerl_do_git_build
    kerl_assert_build_name_unused $argv[3]

    set -l GIT (echo -n "$argv[1]" | $MD5SUM | cut -d " " -f $MD5SUM_FIELD)
    mkdir -p "$KERL_GIT_DIR"
    cd "$KERL_GIT_DIR"
    echo "Checking Erlang/OTP git repository from $argv[1]..."
    if test ! -d "$GIT"
        git clone -q --mirror "$argv[1]" "$GIT" > /dev/null 2>&1
        if test $status -ne 0
            echo "Error mirroring remote git repository"
            return 1
        end
    end
    cd "$GIT"
    git remote update --prune > /dev/null 2>&1
    if test $status -ne 0
        echo "Error updating remote git repository"
        return 1
    end

    rm -Rf "$KERL_BUILD_DIR/$argv[3]"
    mkdir -p "$KERL_BUILD_DIR/$argv[3]"
    cd "$KERL_BUILD_DIR/$argv[3]"
    git clone -l "$KERL_GIT_DIR/$GIT" otp_src_git > /dev/null 2>&1
    if test $status -ne 0
        echo "Error cloning local git repository"
        return 1
    end
    cd otp_src_git
    git checkout $argv[2] > /dev/null 2>&1
    if test $status -ne 0
        git checkout -b $argv[2] $argv[2] > /dev/null 2>&1
    end
    if test $status -ne 0
        echo "Couldn't checkout specified version"
        rm -Rf "$KERL_BUILD_DIR/$argv[3]"
        return 1
    end
    if test ! -x otp_build
        echo "Not a valid Erlang/OTP repository"
        rm -Rf "$KERL_BUILD_DIR/$argv[3]"
        return 1
    end
    set -l LOGFILE "$KERL_BUILD_DIR/$argv[3]/otp_build.log"
    echo "Building Erlang/OTP $argv[3] from git, please wait..."
    ./otp_build autoconf $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1 ; and \
        ./otp_build configure $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1
    if test $status -ne 0
        echo "Build error, see $LOGFILE"
        return 1
    end
    if test -n "$KERL_CONFIGURE_APPLICATIONS"
        find ./lib -maxdepth 1 -type d -exec touch -f {}/SKIP \;
        for i in $KERL_CONFIGURE_APPLICATIONS
            rm ./lib/$i/SKIP
            if test $status -ne 0
                echo "Couldn't prepare '$i' application for building"
                return 1
            end
        end
    end
    if test -n "$KERL_CONFIGURE_DISABLE_APPLICATIONS"
        for i in $KERL_CONFIGURE_DISABLE_APPLICATIONS
            touch -f ./lib/$i/SKIP
            if test $status -ne 0
                echo "Couldn't disable '$i' application for building"
                return 1
            end
        end
    end
    ./otp_build boot -a $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1
    if test $status -ne 0
        echo "Build error, see $LOGFILE"
        return 1
    end
    rm -f "$LOGFILE"
    ./otp_build release -a "$KERL_BUILD_DIR/$argv[3]/release_git" > /dev/null 2>&1
    cd "$KERL_BUILD_DIR/$argv[3]/release_git"
    ./Install $INSTALL_OPT "$KERL_BUILD_DIR/$argv[3]/release_git" > /dev/null 2>&1
    echo "Erlang/OTP $argv[3] from git has been successfully built"
    kerl_list_add builds "git,$argv[3]"
end

function kerl_do_build
    switch "$KERL_SYSTEM"
        case Darwin
            if test (gcc --version | grep llvm | wc -l) = "1"
                if kerl_lion_support $argv[1]
                    set KERL_CONFIGURE_OPTIONS "CFLAGS=-O0 $KERL_CONFIGURE_OPTIONS"
                else
                    if test -x (which gcc-4.2)
                        set KERL_CONFIGURE_OPTIONS "CC=gcc-4.2 $KERL_CONFIGURE_OPTIONS"
                    else
                        set KERL_CONFIGURE_OPTIONS "CC=llvm-gcc-4.2 CFLAGS=-O0 $KERL_CONFIGURE_OPTIONS"
                    end
                end
            end
        case '*'
    end

    kerl_assert_valid_release $argv[1]
    kerl_assert_build_name_unused $argv[2]

    set FILENAME otp_src_$argv[1].tar.gz
    kerl_download "$FILENAME"
    mkdir -p "$KERL_BUILD_DIR/$argv[2]"
    if test ! -d "$KERL_BUILD_DIR/$argv[2]/otp_src_$argv[1]"
        echo "Extracting source code"
        set UNTARDIRNAME $KERL_BUILD_DIR/$argv[2]/otp_src_$argv[1]-kerluntar-%self
        rm -rf "$UNTARDIRNAME"
        mkdir -p "$UNTARDIRNAME"
        cd "$UNTARDIRNAME" ; and tar xfz "$KERL_DOWNLOAD_DIR/$FILENAME" ; and mv * "$KERL_BUILD_DIR/$argv[2]/otp_src_$argv[1]"
        rm -rf "$UNTARDIRNAME"
    end
    echo "Building Erlang/OTP $argv[1] ($argv[2]), please wait..."
    set ERL_TOP "$KERL_BUILD_DIR/$argv[2]/otp_src_$argv[1]"
    cd "$ERL_TOP"
    set -l LOGFILE "$KERL_BUILD_DIR/$argv[2]/otp_build_$argv[1].log"
    if test -n "$KERL_USE_AUTOCONF"
        ./otp_build autoconf $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1 ;and \
            ./otp_build configure $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1
    else
        ./otp_build configure $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1

    end
    if test $status -ne 0
        echo "Build failed, see $LOGFILE"
        kerl_list_remove builds "$argv[1] $argv[2]"
        return 1
    end
    if test -n "$KERL_CONFIGURE_APPLICATIONS"
        find ./lib -maxdepth 1 -type d -exec touch -f {}/SKIP \;
        for i in $KERL_CONFIGURE_APPLICATIONS
            rm ./lib/$i/SKIP
            if test $status -ne 0
                echo "Couldn't prepare '$i' application for building"
                kerl_list_remove builds "$argv[1] $argv[2]"
                return 1
            end
        end
    end
    if [ -n "$KERL_CONFIGURE_DISABLE_APPLICATIONS" ]; then
        for i in $KERL_CONFIGURE_DISABLE_APPLICATIONS
            touch -f ./lib/$i/SKIP
            if [ $status -ne 0 ]
                echo "Couldn't disable '$i' application for building"
                return 1
            end
        end
    end
    ./otp_build boot -a $KERL_CONFIGURE_OPTIONS > "$LOGFILE" 2>&1
    if [ $status -ne 0 ]; then
        echo "Build failed, see $LOGFILE"
        kerl_list_remove builds "$argv[1] $argv[2]"
        return 1
    end
    rm -f "$LOGFILE"
    env ERL_TOP="$ERL_TOP" ./otp_build release -a "$KERL_BUILD_DIR/$argv[2]/release_$argv[1]" > /dev/null 2>&1
    cd "$KERL_BUILD_DIR/$argv[2]/release_$argv[1]"
    ./Install $INSTALL_OPT "$KERL_BUILD_DIR/$argv[2]/release_$argv[1]" > /dev/null 2>&1
    echo "Erlang/OTP $argv[1] ($argv[2]) has been successfully built"
    kerl_list_add builds "$argv[1],$argv[2]"
end

function kerl_do_install
    set -l rel (eval kerl_get_release_from_name $argv[1])
    if test $status -ne 0
        echo "No build named $argv[1]"
        return 1
    end
    mkdir -p "$argv[2]"
    if test ! -d "$argv[2]"
        echo "Destination is not a directory"
        return 1
    end
    set -l absdir (cd "$argv[2]" ;and pwd)
    echo "Installing Erlang/OTP $rel ($argv[1]) in $absdir..."
    set -l ERL_TOP "$KERL_BUILD_DIR/$argv[1]/otp_src_$rel"
    cd "$ERL_TOP"
    env ERL_TOP="$ERL_TOP" ./otp_build release -a "$absdir" > /dev/null 2>&1 ; and cd "$absdir" ; and ./Install $INSTALL_OPT "$absdir" > /dev/null 2>&1
    if test $status -ne 0
        echo "Couldn't install Erlang/OTP $rel ($argv[1]) in $absdir"
        return 1
    end
    kerl_list_add installations "$argv[1] $absdir";
    printf "\
# credits to virtualenv
function kerl_deactivate
    if test -n \"\$_KERL_PATH_REMOVABLE\"
        set -l OLD_PATH (echo \$PATH | sed -e \"s;\$_KERL_PATH_REMOVABLE;;\")
        echo -n (eval set -g -x PATH \$OLD_PATH)
        set -e _KERL_PATH_REMOVABLE
    end
    if test -n \"\$_KERL_MANPATH_REMOVABLE\"
        set -l OLD_MANPATH (echo \$MANPATH | sed -e \"s;\$_KERL_MANPATH_REMOVABLE;;\")
        echo -n (eval set -g -x MANPATH \$OLD_MANPATH)
        set -e _KERL_MANPATH_REMOVABLE
    end
    if test -n \"\$_KERL_SAVED_REBAR_PLT_DIR\"
        set -g REBAR_PLT_DIR '\$_KERL_SAVED_REBAR_PLT_DIR'
        set -e _KERL_SAVED_REBAR_PLT_DIR
    end
    if test -n \"\$_KERL_ACTIVE_DIR\"
        set -e _KERL_ACTIVE_DIR
    end
    if test -n \"\$_KERL_SAVED_PS1\"
        set -g PS1 \"\$_KERL_SAVED_PS1\"
        set -e _KERL_SAVED_PS1
    end
    if test -n \"\$BASH\" -o -n \"\$ZSH_VERSION\"
        hash -r
    end
    if test \"\$argv[1]\" != 'nondestructive'
        functions -e kerl_deactivate
    end
end
kerl_deactivate nondestructive

set -g -x _KERL_SAVED_REBAR_PLT_DIR \"\$REBAR_PLT_DIR\"
set -g -x _KERL_PATH_REMOVABLE '$absdir/bin'
set -g -x PATH \$_KERL_PATH_REMOVABLE \$PATH
set -g -x _KERL_MANPATH_REMOVABLE '$absdir/man'
set -g -x MANPATH \$_KERL_MANPATH_REMOVABLE \$MANPATH
set -g -x REBAR_PLT_DIR '$absdir'
set -g -x _KERL_ACTIVE_DIR '$absdir'
if test -f \"\$KERL_CONFIG\"
    . \"\$KERL_CONFIG\"
end
# TODO
if test -n \"\$KERL_ENABLE_PROMPT\"
    set -g -x _KERL_SAVED_PS1 \"\$PS1\"
    set -g -x PS1 \"($argv[1])\$PS1\"
    export PS1
end
if test -n \"\$BASH\" -o -n \"\$ZSH_VERSION\"
    hash -r
end
" > "$absdir/activate"
    if test "$rel" != "git"
        if test -n "$KERL_INSTALL_MANPAGES"
            echo "Fetching and installing manpages..."
            set -l FILENAME otp_doc_man_$rel.tar.gz
            kerl_download "$FILENAME"
            echo "Extracting manpages"
            cd "$absdir" ;and tar xfz "$KERL_DOWNLOAD_DIR/$FILENAME"
        end

        if test -n "$KERL_INSTALL_HTMLDOCS"
            echo "Fetching and installing HTML docs..."
            set -l FILENAME "otp_doc_html_$rel.tar.gz"
            kerl_download "$FILENAME"
            echo "Extracting HTML docs"
            cd "$absdir" ; and mkdir -p html ; and tar -C "$absdir/html" -xzf "$KERL_DOWNLOAD_DIR/$FILENAME"
        end
    else
        set -l rel (kerl_get_newest_valid_release)
        if test $status -ne 0
            echo "No newest valid release"
            return 1
        end

        if test -n "$KERL_INSTALL_MANPAGES"
            echo "CAUTION: Fetching and installing newest ($rel) manpages..."
            set -l FILENAME otp_doc_man_$rel.tar.gz
            kerl_download "$FILENAME"
            echo "Extracting manpages"
            cd "$absdir" ;and tar xfz "$KERL_DOWNLOAD_DIR/$FILENAME"
        end

        if test -n "$KERL_INSTALL_HTMLDOCS"
            echo "CATION: Fetching and installing newest ($rel) HTML docs..."
            set -l FILENAME "otp_doc_html_$rel.tar.gz"
            kerl_download "$FILENAME"
            echo "Extracting HTML docs"
            cd "$absdir" ;and mkdir -p html ;and tar -C "$absdir/html" -xzf "$KERL_DOWNLOAD_DIR/$FILENAME"
        end
    end

    echo "You can activate this installation running the following command:"
    echo ". $absdir/activate"
    echo "Later on, you can leave the installation typing:"
    echo "kerl_deactivate"
end

function kerl_do_deploy
    if test -z "$argv[1]"
        echo "No host given"
        return 1
    end
    set -l host $argv[1]

    kerl_assert_valid_installation "$argv[2]"
    set -l rel (kerl_get_name_from_install_path "$argv[2]")
    set -l path $argv[2]
    set -l remotepath $path

    if test ! -z "$argv[3]"
        set -l remotepath $argv[3]
    end

    ssh $KERL_DEPLOY_SSH_OPTIONS $host true > /dev/null 2>&1
    if test $status -ne 0
        echo "Couldn't ssh to $host"
        return 1
    end

    echo "Cloning Erlang/OTP $rel ($path) to $host ($remotepath) ..."

    rsync -aqz -e "ssh $KERL_DEPLOY_SSH_OPTIONS" $KERL_DEPLOY_RSYNC_OPTIONS "$path/" "$host:$remotepath/"
    if test $status -ne 0
        echo "Couldn't rsync Erlang/OTP $rel ($path) to $host ($remotepath)"
        return 1
    end

    # TODO
    ssh $KERL_DEPLOY_SSH_OPTIONS $host "cd \"$remotepath\" ;and env ERL_TOP=\`pwd\` ./Install $INSTALL_OPT \`pwd\` > /dev/null 2>&1"
    if test $status -ne 0
        echo "Couldn't install Erlang/OTP $rel to $host ($remotepath)"
        return 1
    end

    # TODO
    ssh $KERL_DEPLOY_SSH_OPTIONS $host "cd \"$remotepath\" ;and sed -i -e \"s#$path#\`pwd\`#g\" activate"
    if test $status -ne 0
        echo "Couldn't completely install Erlang/OTP $rel to $host ($remotepath)"
        return 1
    end

    echo "On $host, you can activate this installation running the following command:"
    echo ". $remotepath/activate"
    echo "Later on, you can leave the installation typing:"
    echo "kerl_deactivate"
end

function kerl_list_print
    if test -f $KERL_BASE_DIR/otp_$argv[1]
        # TODO
        if test (cat "$KERL_BASE_DIR/otp_$argv[1]" | wc -l| sed -e 's/^[[:space:]]*\(.?*\)[[:space:]]*$/\1/') != "0"
            echo $argv | read -l first second
            if test -z $second
                cat "$KERL_BASE_DIR/otp_$argv[1]"
            else
                echo (cat "$KERL_BASE_DIR/otp_$argv[1]")
            end
            return 0
        end
    end
    echo "There are no $argv[1] available"
end

function kerl_list_add
    if test -f "$KERL_BASE_DIR/otp_$argv[1]"
        for l in (cat "$KERL_BASE_DIR/otp_$argv[1]")
            if test "$l" = "$argv[2]"
                return 1
            end
        end
        echo "$argv[2]" >> "$KERL_BASE_DIR/otp_$argv[1]"
    else
        echo "$argv[2]" > "$KERL_BASE_DIR/otp_$argv[1]"
    end
end

function kerl_list_remove
    if test -f "$KERL_BASE_DIR/otp_$argv[1]"
        sed $SED_OPT -i -e "/^.*$argv[2]\$/d" "$KERL_BASE_DIR/otp_$argv[1]"
    end
end

function kerl_list_has
    if test -f "$KERL_BASE_DIR/otp_$argv[1]"
        grep $argv[2] "$KERL_BASE_DIR/otp_$argv[1]" > /dev/null 2>&1 ;and return 0
    end
    return 1
end

function kerl_list_usage
    echo "usage: kerl list <releases|builds|installations>"
end

function kerl_delete_usage
    echo "usage: kerl delete <build|installation> <build_name or path>"
end

function kerl_cleanup_usage
    echo "usage: kerl cleanup <build_name|all>"
end

function kerl_update_usage
    echo "usage: kerl update releases"
end

function kerl_get_active_path
    if test -n "$_KERL_ACTIVE_DIR"
        echo $_KERL_ACTIVE_DIR
    end
    return 0
end

function kerl_get_name_from_install_path
    if test -f "$KERL_BASE_DIR/otp_installations"
        grep -F "$argv[1]" "$KERL_BASE_DIR/otp_installations" | cut -d ' ' -f 1
    end
    return 0
end

function kerl_do_active
    set -l ACTIVE_PATH (kerl_get_active_path)
    if test -n "$ACTIVE_PATH"
        echo "The current active installation is:"
        echo $ACTIVE_PATH
        return 0
    else
        echo "No Erlang/OTP kerl installation is currently active"
        return 1
    end
end

function kerl_download
    if test ! -f "$KERL_DOWNLOAD_DIR/$argv[1]"
        echo "Downloading $argv[1] to $KERL_DOWNLOAD_DIR"
        mkdir -p "$KERL_DOWNLOAD_DIR"
        curl -L "$ERLANG_DOWNLOAD_URL/$argv[1]" > "$KERL_DOWNLOAD_DIR/$argv[1]"
        kerl_update_checksum_file
    end
    kerl_ensure_checksum_file
    echo "Verifying archive checksum..."
    set -l SUM (eval $MD5SUM "$KERL_DOWNLOAD_DIR/$argv[1]" | cut -d " " -f $MD5SUM_FIELD)
    set -l ORIG_SUM (grep -F "$argv[1]" "$KERL_DOWNLOAD_DIR/MD5" | cut -d " " -f 2)
    if test "$SUM" != "$ORIG_SUM"
        echo "Checksum error, check the files in $KERL_DOWNLOAD_DIR"
        return 1
    end
    echo "Checksum verified ($SUM)"
end

function kerl
    if test (count $argv) -lt 1
        kerl_usage
        return 127
    end

    switch "$argv[1]"
        case build
            if test (count $argv) = 5
                if test "$argv[2]" != "git"
                    echo "usage: kerl $argv[1] $argv[2] <git_url> <git_version> <build_name>"
                    return 1
                end
                kerl_do_git_build $argv[3] $argv[4] $argv[5]
            else if test (count $argv) = 3
                kerl_do_build $argv[2] $argv[3]
            else
                echo "usage: kerl $argv[1] <release> <build_name>"
                echo "usage: kerl $argv[1] git <git_url> <git_version> <build_name>"
                return 1
            end
        case install
            if test (count $argv) -lt 2
                echo "usage: kerl $argv[1] <build_name> [directory]"
                return 1
            end
            if test (count $argv) -eq 3
                if test "$argv[3]" = "$HOME"
                    echo "Refusing to install in $HOME, this is a bad idea."
                    return 1
                else
                    kerl_do_install $argv[2] "$argv[3]"
                end
            else
                if test -z "$KERL_DEFAULT_INSTALL_DIR"
                    if test "$PWD" = "$HOME"
                        echo "Refusing to install in $HOME, this is a bad idea."
                        return 1
                    else
                        kerl_do_install $argv[2] .
                    end
                else
                    kerl_do_install $argv[2] "$KERL_DEFAULT_INSTALL_DIR/$argv[2]"
                end
            end
        case deploy
            if test (count $argv) -lt 2
                echo "usage: kerl $argv[1] <[user@]host> [directory] [remote_directory]"
                return 1
            end
            if test (count $argv) -eq 4
                kerl_do_deploy $argv[2] "$argv[3]" "$argv[4]"
            else
                if test (count $argv) -eq 3
                    kerl_do_deploy $argv[2] "$argv[3]"
                else
                    kerl_do_deploy $argv[2] .
                end
            end
        case update
            if test (count $argv) -lt 2
                kerl_update_usage
                return 1
            end
            switch "$argv[2]"
                case releases
                    rm -f "$KERL_BASE_DIR/otp_releases"
                    kerl_check_releases
                    echo "The available releases are:"
                    kerl_list_print releases spaces
                case '*'
                    kerl_update_usage
                    return 1
                end
        case ls list
            if test (count $argv) -ne 2
                kerl_list_usage
                return 1
            end
            switch "$argv[2]"
                case releases
                    kerl_check_releases
                    kerl_list_print $argv[2] space
                    echo "Run \"kerl update releases\" to update this list from erlang.org"
                case builds
                    kerl_list_print $argv[2]
                case installations
                    kerl_list_print $argv[2]
                case '*'
                    echo "Cannot list $argv[2]"
                    kerl_list_usage
                    return 1
            end
        case delete
            if test (count $argv) -ne 3
                kerl_delete_usage
                return 1
            end
            switch "$argv[2]"
                case build
                    set -l rel (kerl_get_release_from_name $argv[3])
                    if test -d "$KERL_BUILD_DIR/$argv[3]"
                        rm -Rf "$KERL_BUILD_DIR/$argv[3]"
                    else
                        if test -z "$rel"
                          echo "No build named $argv[3]"
                          return 1
                        end
                    end
                    kerl_list_remove $argv[2]s "$rel,$argv[3]"
                    echo "The $argv[3] build has been deleted"
                case installation
                    kerl_assert_valid_installation "$argv[3]"
                    rm -Rf "$argv[3]"
                    set -l escaped (echo "$argv[3]" | sed $SED_OPT -e 's#/$##' -e 's#\/#\\\/#g')
                    kerl_list_remove $argv[2]s "$escaped"
                    echo "The installation in $argv[3] has been deleted"
                case '*'
                    echo "Cannot delete $argv[2]"
                    kerl_delete_usage
                    return 1
            end
        case active
            if test ! kerl_do_active
                return 1;
            end
        case status
            echo "Available builds:"
            kerl_list_print builds
            echo "----------"
            echo "Available installations:"
            kerl_list_print installations
            echo "----------"
            kerl_do_active
            return 0
        case prompt
            set -l FMT " (%s)"
            if test -n "$argv[2]"
                set -l FMT "$argv[2]"
            end
            set -l ACTIVE_PATH (kerl_get_active_path)
            if test -n "$ACTIVE_PATH"
                set -l ACTIVE_NAME (kerl_get_name_from_install_path "$ACTIVE_PATH")
                if test -z "$ACTIVE_NAME"
                    set -l VALUE (basename "$ACTIVE_PATH")*
                else
                    VALUE="$ACTIVE_NAME"
                end
                printf "$FMT" "$VALUE"
            end
            return 0
        case cleanup
            if test (count $argv) -ne 2
                kerl_cleanup_usage
                return 1
            end
            switch "$argv[2]"
                case all
                    echo "Cleaning up compilation products for ALL builds"
                    rm -rf $KERL_BUILD_DIR/*
                    rm -rf $KERL_DOWNLOAD_DIR/*
                    rm -rf $KERL_GIT_DIR/*
                    echo "Cleaned up all compilation products under $KERL_BUILD_DIR"
                case '*'
                    echo "Cleaning up compilation products for $argv[3]"
                    rm -rf $KERL_BUILD_DIR/$argv[3]
                    echo "Cleaned up all compilation products under $KERL_BUILD_DIR"
            end
        case '*'
            echo "unknown command: $argv[1]"; kerl_usage; return 1
    end
end

kerl $argv
