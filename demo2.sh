#!/bin/sh
# Simple script to explore drupal
# DO NOT RUN ON SYSTEMS WITH MYSQL INSTALLED.  IT WILL NUKE ALL MYSQL DATA.

set -e

drupalmajor=7

# Don't use this password if your MySQL server is on the public internet
sqlrootpw="q9z7a1"

# Let's keep our git client at $srctop/$projectname
# Always quote srctop and giturl, since $HOME might have spaces in it.
srctop="$HOME"/drupaldemo.tmp
projectname="busydrupal"

# Ubuntu packages we need to install and uninstall in order to
# reproduce everything cleanly.
pkgs="mysql-client mysql-server drush php5-gd apache2 libapache2-mod-php5"

do_nuke() {
    echo "=== Warning, destroying all mysql data; also removing $srctop ==="
    set -x
    sudo apt-get remove $pkgs || true
    sudo apt-get purge $pkgs || true
    sudo apt-get autoremove || true
    sudo rm -rf "$srctop"
}

do_deps() {
    echo "When prompted, enter $sqlrootpw for the sql root password."
    sleep 4
    set -x
    sudo apt-get install -y $pkgs
}

do_initgit() {
    set -x
    # Prepare our master project repository
    mkdir -p "$srctop"/$projectname
    cd "$srctop"/$projectname
    git init

    # Grab drupal
    drush dl drupal-$drupalmajor
    eval mv drupal-$drupalmajor*/* .
    eval mv drupal-$drupalmajor*/.htaccess .
    eval mv drupal-$drupalmajor*/.gitignore .
    rmdir drupal-$drupalmajor*

    # Add a .gitignore file
    cat > .gitignore <<_EOF_
# Ignore configuration files that may contain sensitive information.
sites/*/settings*.php
# Ignore paths that contain user-generated content.
sites/*/files
sites/*/private
_EOF_
    git add .gitignore
    git commit -m "First commit for project $projectname"
}

do_install() {
    if ! test -d "$srctop"/$projectname
    then
        echo "Please run '$0 initgit' first."
        exit 1
    fi
    set -x
    cd "$srctop"/$projectname
    drush si --db-url=mysql://root:$sqlrootpw@localhost/drupal --account-name=drupal --account-pass=drupal

    # Thanks to http://befused.com/drupal/drush-devel-generate
    drush dl devel
    drush en devel -y
    drush en devel_generate -y

    # FIXME: This is insecure, but required to pass the status report tests
    chmod 777 sites/default/files

    wwwdir=/var/www
    if test -d /var/www/html
    then
        wwwdir=/var/www/html
    fi
    echo "Now, if your web server is running, and this directory"
    echo "is visible from it, and you have AllowOverrides turned on"
    echo "for this directory, you ought to be able to log into the"
    echo "drupal instance via a web browser with username drupal, password drupal."
    echo "You might need to do something like 'sudo ln -s $srctop/$projectname $wwwdir/$projectname"
    echo "To turn on overrides, you might need to do 'sudo a2enmod rewrite'"
    echo "and add a paragraph for $wwwdir/$projectname in" /etc/apache2/sites-enabled/000-default*
    echo "per https://drupal.org/getting-started/clean-urls"
    xdg-open http://localhost/$projectname 2> /dev/null || true
}

do_install_calendar7() {
    echo Home page: https://drupal.org/project/calendar
    echo See related tutorials:
    echo  https://drupal.org/node/1477602
    echo  http://www.ostraining.com/blog/drupal/calendar-in-drupal/
    echo  http://drupalize.me/series/calendars-drupal-7
    set -x
    cd "$srctop"/$projectname

    drush -y dl ctools views date calendar 
    drush -y en ctools views views_ui date date_popup calendar

    # For repeating dates, need a bit more
    drush -y dl date_repeat_instance
    drush -y en date_repeat date_repeat_field date_repeat_instance

    # Work around bug https://drupal.org/node/1471400
    # FIXME: remove this once this bug is fixed
    wget https://drupal.org/files/calendar-php54-1471400-58.patch
    cat calendar-php54-1471400-58.patch | \
        (cd sites/all/modules/calendar; patch -p1)

    xdg-open http://www.ostraining.com/blog/drupal/calendar-in-drupal/ 2> /dev/null || true
    cat << _EOF_
Calendar module enabled.  Now perform the following steps in the gui
to add a calendar view to the left sidebar:

1. Add a view for the calendar
 Structure > Views > Add view from template
 "A calendar view of the 'created' field in the 'comment' base table" > add
 Continue, Save

2. Put the block in a region
 Structure > Blocks
 "View: Calendar" > Sidebar First
 Save Blocks

Opening http://www.ostraining.com/blog/drupal/calendar-in-drupal/
for a more thorough explanation of how to get started with calendars.

Notes:
If you can't seem to enter repeating dates, be aware that
the Date Repeat module has to be enabled before creating
your content type.  (This script should have already done this for you.)

If you get
"calendar_plugin_style: A date argument is required when using the calendar style, but it is missing or is not using the default date."
when displaying your calendar, you've hit
https://drupal.org/node/1490892
To fix, edit your view,
- add a 'Contextual Filter',
- set 'Provide default value' to 'Current Date'
- save

If you get 
"Undefined index: tz in date_ical_date() (line 620 of ../modules/date/date_api/date_api_ical.inc)"
when editing a repeating event, apply the patch from
https://drupal.org/node/1633146
_EOF_
}

do_install_calendar() {
    case $drupalmajor in
    7) do_install_calendar7 ;;
    *) echo "what?"; exit 1;;
    esac
}

do_install_features() {
    cd "$srctop"/$projectname
    drush dl features
    drush en features -y
}

do_fake() {
    n=$1
    if test "$n" = "" || test $n -lt 1
    then
        echo "Please specify a node count greater than zero."
        exit 1
    fi
    set -x
    cd "$srctop"/$projectname

    # Use generate-content module
    # See also http://befused.com/drupal/drush-devel-generate

    case $drupalmajor in
    7)
      echo "Working around problem (in drupal 7 only?) where generated content images don't show up"
      for size in large medium
      do
        mkdir -p sites/default/files/styles/$size/public
        if ! test -d sites/default/files/styles/$size/public/field/.
        then
            ln -s ../../../field sites/default/files/styles/$size/public
        fi
      done
      ;;
    *) echo "what?"; exit 1;;
    esac

    echo "============= Fake: $n fake nodes ============="
    drush generate-content $n --kill
}

do_benchmark() {
    c=$1
    if test "$c" = "" || test $c -lt 1
    then
        echo "Please specify a session count greater than zero."
        exit 1
    fi
    set -x
    cd "$srctop"/$projectname
    # Find first valid page
    node=`mysql -u root -p$sqlrootpw drupal -e "select nid from node limit 0,1;" | awk '/[0-9]/{print }'`
    url=http://localhost/$projectname/node/$node
    tries=`expr $c '*' 3`
    echo "============= Benchmark: $c concurrent sessions ============="
    ab -n $tries -c $c $url
}

do_backup() {
    f="$1"
    f="`echo $f`"
    case "$f" in
    /*.tar.gz);;
    *)
        echo "Please specify an absolute path to a .tar.gz file to back up to... $f doesn't look like one."
        exit 1
        ;;
    esac
    set -x
    cd "$srctop"/$projectname
    drush vset maintenance_mode 1
    # FIXME: this list doesn't work for things like cck?
    drush pm-list | grep "Enabled" | sed 's/.*(//;s/).*//' > backup-modules.txt
    # Restoring is really slow without turning off autocommit, etc.
    echo "
SET autocommit=0;
SET unique_checks=0;
SET foreign_key_checks=0;" > backup-mysql.dump
    mysqldump -u root -p$sqlrootpw drupal >> backup-mysql.dump
echo "COMMIT;" >> backup-mysql.dump
    tar -czvf "$1" --exclude libraries --exclude modules backup-modules.txt backup-mysql.dump sites
    drush vset maintenance_mode 0
}

do_restore() {
    f="$1"
    case "$f" in
    /*.tar.gz);;
    *)
        echo "Please specify an absolute path to a .tar.gz file to restore from."
        exit 1
        ;;
    esac
    set -x
    cd "$srctop"/$projectname
    tar -xzvf "$f"
    drush vset maintenance_mode 1
    drush dl `cat backup-modules.txt`
    drush en `cat backup-modules.txt`
    # Use pv to get progress bar
    pv backup-mysql.dump | mysql -u root -p$sqlrootpw drupal
    drush vset maintenance_mode 0
}

usage() {
    echo "Usage: $0 [nuke|deps|initgit|clone|install|fake Nodes|bench Sessions|nuke]"
    echo "Example of how to create a Drupal project using git, and benchmark it."
    echo "DO NOT RUN ON SYSTEMS WITH MYSQL INSTALLED.  IT WILL NUKE ALL MYSQL DATA."
    echo "Run each of the verb in order (e.g. $0 nuke; $0 deps; $0 initgit; ...)"
    echo "The fake verb takes an argument: how many fake nodes to create"
    echo "The bench verb takes an argument: how many simultaneous users."
}

case $1 in
nuke) do_nuke;;
deps) do_deps;;
initgit) do_initgit;;
install) do_install;;
install_calendar) do_install_calendar;;
install_features) do_install_features;;
fake) do_fake $2;;
bench) do_benchmark $2;;
backup) do_backup "$2";;
restore) do_restore "$2";;
*) usage; exit 1;;
esac
