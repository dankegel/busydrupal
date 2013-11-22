#!/bin/sh
# Simple script to explore drupal
# DO NOT RUN ON SYSTEMS WITH MYSQL INSTALLED.  IT WILL NUKE ALL MYSQL DATA.

set -e

# Select Drupal 6 or Drupal 7
if false
then
    drupalmajor=6
    drupalminor=28
else
    drupalmajor=7
    drupalminor=24
fi

# Don't use this password if your MySQL server is on the public internet
sqlrootpw="q9z7a1"

# Let's keep our master git repository in $srctop/bare/$projectname.git
# (in the real world, it would be on a remote machine)
# and our git client at $srctop/$projectname.git
# And let's call our git branch $projectname-master
# Always quote srctop and giturl, since $HOME might have spaces in it.
srctop="$HOME"/drupaldemo.tmp
projectname="busydrupal"
giturl="$srctop"/bare/$projectname.git

# Ubuntu packages we need to install and uninstall in order to
# reproduce everything cleanly.
pkgs="mysql-client mysql-server drush"

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
    sleep 3
    set -x
    sudo apt-get install -y $pkgs
}

do_initgit() {
    # Set up this project's git repo from the horse's mouth
    # See https://drupal.org/node/803746
    if test -d "$srctop"
    then
        echo "$srctop already exists.  Please run '$0 nuke' first if you want to start over."
        exit 1
    fi
    set -x
    # Prepare our master project repository
    mkdir -p "$srctop"/bare
    cd "$srctop"/bare
    git init --bare $projectname.git
    # Clone our initial git client from drupal.org, add a .gitignore, and push it to our master project repository
    cd "$srctop"
    git clone --branch $drupalmajor.x http://git.drupal.org/project/drupal.git $projectname.git
    cd "$projectname".git
    # Rewind to most recent release (FIXME: determine this dynamically)
    git reset --hard $drupalmajor.$drupalminor
    # Create our own branch
    git checkout -b $projectname-master
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
    git remote rename origin drupal
    git remote add origin "$giturl"
    git push origin $projectname-master
    cd "$srctop"
    rm -rf $projectname.git
}

do_clone()
{
    set -x
    # Clone this project's git repo locally
    mkdir -p "$srctop"
    cd "$srctop"
    git clone --branch $projectname-master "$giturl" $projectname.git
    # Also add reference to upstream for updates
    cd $projectname.git
    git remote add drupal http://git.drupal.org/project/drupal.git
    cd ..
}

do_install() {
    if ! test -d "$srctop"/$projectname.git
    then
        echo "Please run '$0 clone' first."
        exit 1
    fi
    set -x
    cd "$srctop"/$projectname.git
    drush si --db-url=mysql://root:$sqlrootpw@localhost/drupal --account-name=drupal --account-pass=drupal

    # Thanks to http://befused.com/drupal/drush-devel-generate
    drush dl devel
    drush en devel -y
    drush en devel_generate -y

    # FIXME: This is insecure, but required to pass the status report tests
    chmod 777 sites/default/files

    echo "Now, if your web server is running, and this directory"
    echo "is visible from it, and you have AllowOverrides turned on"
    echo "for this directory, you ought to be able to log into the"
    echo "drupal instance via a web browser with username drupal, password drupal."
    echo "You might need to do something like 'sudo ln -s $srctop/$projectname.git /var/www/$projectname"
    echo "To turn on overrides, you might need to do 'sudo a2enmod rewrite'"
    echo "and add a paragraph for /var/www/$projectname in /etc/apache2/sites-enabled/000-default"
    xdg-open http://localhost/$projectname
}

do_install_calendar6() {
    # Home page: https://drupal.org/project/calendar
    # See related tutorials:
    #  http://vimeo.com/6544779
    #  http://gotdrupal.com/videos/drupal-calendar
    set -x
    cd "$srctop"/$projectname.git

    # Date Popup requires jquery_ui, but the command
    #   "drush dl jquery_ui; drush en jquery_ui"
    # will fail with message
    #   "Module jquery_ui doesn't meet the requirements to be enabled.
    #   The jQuery UI plugin is missing. Download and extract it
    #   into the sites/all/libraries directory. Rename the extracted
    #   folder to jquery.ui. (Currently using jQuery UI Not found)"
    # so do that first.
    mkdir -p sites/all/libraries
    wget https://jquery-ui.googlecode.com/files/jquery.ui-1.6.zip
    unzip jquery.ui-1.6.zip -d sites/all/libraries
    mv sites/all/libraries/jquery.ui-1.6/ sites/all/libraries/jquery.ui

    drush -y dl jquerymenu-6.x-3.3 cck views date jquery_ui calendar
    drush -y en cck views views_ui date date_popup jquery_ui calendar

    # Some tutorial videos use the admin menu, so install that, too
    drush -y dl admin_menu
    drush -y en admin_menu

    echo "Calendar module enabled.  Now enable it as described in this tutorial:"
    xdg-open http://vimeo.com/6544779
    echo "or this one:"
    xdg-open https://drupal.org/node/1775076
    cat << _EOF_
Then put the block in a region, e.g.
  Site Building > Blocks > List
  "Calendar" > Left Sidebar
  Save Blocks
_EOF_
}

do_install_calendar7() {
    echo Home page: https://drupal.org/project/calendar
    echo See related tutorials:
    echo  https://drupal.org/node/1477602
    echo  http://www.ostraining.com/blog/drupal/calendar-in-drupal/
    echo  http://drupalize.me/series/calendars-drupal-7
    set -x
    cd "$srctop"/$projectname.git

    drush -y dl ctools views date calendar
    drush -y en ctools views views_ui date calendar

    # Work around bug https://drupal.org/node/1471400
    # FIXME: remove this once this bug is fixed
    wget https://drupal.org/files/calendar-php54-1471400-58.patch
    cat calendar-php54-1471400-58.patch | \
        (cd sites/all/modules/calendar; patch -p1)

    xdg-open http://www.ostraining.com/blog/drupal/calendar-in-drupal/
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
_EOF_
}

do_install_calendar() {
    case $drupalmajor in
    6) do_install_calendar6 ;;
    7) do_install_calendar7 ;;
    esac
}

do_fake() {
    n=$1
    if test "$n" = "" || test $n -lt 1
    then
        echo "Please specify a node count greater than zero."
        exit 1
    fi
    set -x
    cd "$srctop"/$projectname.git

    # Use generate-content module
    # See also http://befused.com/drupal/drush-devel-generate

    case $drupalmajor in
    6) ;;
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
    cd "$srctop"/$projectname.git
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
    cd "$srctop"/$projectname.git
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
    cd "$srctop"/$projectname.git
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
clone) do_clone;;
install) do_install;;
install_calendar) do_install_calendar;;
fake) do_fake $2;;
bench) do_benchmark $2;;
backup) do_backup "$2";;
restore) do_restore "$2";;
*) usage; exit 1;;
esac
