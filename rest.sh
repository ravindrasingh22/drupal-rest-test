#!/usr/bin/env bash

if [ ! -f ./rest.ini ] ; then
  echo "No INI file found."
  echo "- Please copy rest.ini.dist to rest.ini and make sure it fits your config."
  exit
fi
[ -d ./data ] || mkdir ./data
source ./rest.ini

# Enable command echo
# set -x

HAL_HEADER="Accept: application/hal+json"
JSON_HEADER="Accept: application/json"

# defaults according to /core/modules/rest/config/install
ACCEPT_HEADER=$HAL_HEADER

USER_1_NAME=`echo $USER_1 | cut -d: -f1`
USER_1_PASS=`echo $USER_1 | cut -d: -f2`

CURL_USERNAME=`echo $CURL_USER | cut -d: -f1`
CURL_PASSWORD=`echo $CURL_USER | cut -d: -f2`

# Only show help when no arguments found or unknown command
ARGS=$#

echo "Running: $1"

# Define some macros

## ALIAS ##  - full-install      : Quickly installs and configures an empty site for HAL and query for content
if [ "$1" == "full-install" ]; then
  $0 install install-modules enable-modules install-config views
  $0 generate-content rest-resources perms config
  $0 hal-content hal-content-anon
  $0 rest-content rest-content-anon
  exit;
fi

## ALIAS ##  - hal-content       : Query as admin for all HAL configured content
if [ "$1" == "hal-content" ]; then
  $0 hal nodes node comment user file
  exit;
fi

## ALIAS ##  - hal-content-anon  : Query as anonymous for all HAL configured content
if [ "$1" == "hal-content-anon" ]; then
  $0 hal anon nodes node comment user file
  exit;
fi

## ALIAS ##  - hal-9000          : Generate 42 nodes
if [ "$1" == "hal-9000" ]; then
  echo "I can't let you do that, $USER."
  exit;
fi

## ALIAS ##  - rest-content      : Query as $CURL_USERNAME for all rest configured content
if [ "$1" == "rest-content" ]; then
  $0 rest nodes node comment user file
  exit;
fi

## ALIAS ##  - rest-content-anon : Query as anonymous for all rest configured content
if [ "$1" == "rest-content-anon" ]; then
  $0 rest anon nodes node comment user file
  exit;
fi

##  - install           : Reinstall drupal enable modules and setup config
if [ "$1" == "install" ]; then
  drush $DRUSH_ALIAS --yes --notify site-install

  # TODO: split this into enable?
  drush $DRUSH_ALIAS user-password $USER_1_NAME --password=$USER_1_PASS

  shift
fi

##  - install-modules   : Completely reinstall! contrib modules: devel rest_ui oauth
if [ "$1" == "install-modules" ]; then
  # install helpers and make sure to grab latest versions.
  drush $DRUSH_ALIAS --yes dl $PACKAGE_HANDLER devel-1.x
  drush $DRUSH_ALIAS --yes dl $PACKAGE_HANDLER restui-1.x
  drush $DRUSH_ALIAS --yes dl $PACKAGE_HANDLER oauth-1.x

  shift
fi

##  - enable-modules    : Enable contrib modules: devel rest_ui oauth
if [ "$1" == "enable-modules" ]; then

  # defaults according to /core/modules/rest/config/install/rest.yml
  drush $DRUSH_ALIAS --yes pm-enable rest hal basic_auth

  # enable helpers
  drush $DRUSH_ALIAS --yes pm-enable devel_generate simpletest restui

  # This may fail due to PECL and drush does not enable others on same command
  # https://github.com/drush-ops/drush/pull/1331
  drush $DRUSH_ALIAS --yes pm-enable oauth

  drush $DRUSH_ALIAS pm-list --no-core --status=enabled
  shift
fi

##  - install-config    : Copies the .dist files
if [ "$1" == "install-config" ]; then
  [ -f ./rest.yml ] || cp ./rest.yml.dist ./rest.yml
  [ -f ./views.view.rest_nodes.yml ] || cp ./views.view.rest_nodes.yml.dist ./views.view.rest_nodes.yml

  shift
fi

##  - views             : Tries to install a view for the 'nodes' FIXME
if [ "$1" == "views" ]; then
  echo "=============================="
  echo "FIXME: $1"
  echo "-------------------------------"
  echo "Please add Rest export display on path /node."
  echo "------------------------------"
  drush $DRUSH_ALIAS user-login admin admin/structure/views/view/frontpage
  echo "================================="
  echo ""
  shift
fi

##  - generate-content  : Generated the needed data: users nodes comment
if [ "$1" == "generate-content" ]; then

  drush $DRUSH_ALIAS generate-users 3

  # Add terms as they are entity references we could test against.
  drush $DRUSH_ALIAS generate-terms tags 4

  # Generate a node + comment
  drush $DRUSH_ALIAS generate-content --types=article 2 3

  shift
fi

##  - rest-resources    : Enable the modules and load config providing the ReST API's HAL and json.
if [ "$1" == "rest-resources" ]; then
  drush $DRUSH_ALIAS --yes pm-enable hal

  cat ./rest.yml | drush $DRUSH_ALIAS config-set --yes --format=yaml rest.settings resources.entity -
  drush $DRUSH_ALIAS cache-rebuild

  shift
fi

MODULE_NAME="hal"

##  - rest              : Set Accept-header to json.
if [ "$1" == "rest" ]; then
  ACCEPT_HEADER=$JSON_HEADER
  MODULE_NAME="rest"
  shift
fi

##  - hal               : Set Accept-header ti hal+json.
if [ "$1" == "hal" ]; then
  ACCEPT_HEADER=$HAL_HEADER
  MODULE_NAME="hal"
  shift
fi

##  - perms             : Set the known permissions for the exposed rest resources.
if [ "$1" == "perms" ]; then
  echo "--------------------------------------"
  echo "Setting permissions"

  for role in "anonymous" "administrator"; do

    ROLES="create article content,edit any article content,delete any article content"

    for entity in "node" "comment" "user" "taxonomy_term" ; do
      ROLES="$ROLES,restful get entity:$entity,restful post entity:$entity,restful delete entity:$entity,restful patch entity:$entity"
    done
    drush $DRUSH_ALIAS --notify role-add-perm $role "$ROLES"
  done

  shift
fi

##  - config            : Show the config and provides login URL
if [ "$1" == "config" ]; then
  echo "--------------------------------------"
  echo "Settings:"
  echo
  echo "- drush   : $DRUSH_ALIAS"
  echo "- accept  : $ACCEPT_HEADER"
  echo "- node    : $RESOURCE_node"
  echo "- comment : $RESOURCE_comment"
  echo "- user    : $RESOURCE_user"
  echo
  echo "--------------------------------------"
  echo "rest.settings:"
  echo
  drush $DRUSH_ALIAS config-get rest.settings

  echo "--------------------------------------"
  echo "Database 'rest.entity.' config:"
  echo
  drush $DRUSH_ALIAS sql-query "SELECT name, path FROM router WHERE name LIKE 'rest.entity.%';"

  echo "--------------------------------------"
  echo "# Verify config manually"
  drush $DRUSH_ALIAS user-login admin admin/config/services/rest

  shift
fi

##  - web               : Alias for drush user-login
if [ "$1" == "web" ]; then
  drush $DRUSH_ALIAS user-login admin admin/config/services/rest
  shift
fi

##  - anon              : Swith to anonymous user which may not view profile
if [ "$1" == "anon" ]; then
  CURL_USERNAME="anonymous"
  CURL_PASSWORD=""
  shift
fi

##  - lang              : Swith to language
LANG=en
if [ "$1" == "lang" ]; then
  shift
  LANG=$1
  shift
fi


# When adding new entity make sure to add it's RESOURCE_ above
##  - nodes             : Query the configured views is successful. FIXME
##  - node              : Query for a node resource
##  - comment           : Query for a comment resource
##  - user              : Query for a user resource
for entity in "nodes" "node" "comment" "user" "file" ; do
  if [ "$1" == "$entity" ]; then
    echo ""
    echo "========== $entity =============="
    NAME="RESOURCE_$1"
    RESOURCE=${!NAME}
    FILE_NAME=./data/${CURL_USERNAME}-${MODULE_NAME}-$1.json
    set -x
    curl \
      --user $CURL_USER \
      --header "$ACCEPT_HEADER" \
      --request GET $URL/$RESOURCE > $FILE_NAME
    #  --header "Accept-Language: $LANG" \
    #  --header "Content-Language: $LANG" \
    set +x
    echo ============ RESPONSE : $RESOURCE ============
    cat $FILE_NAME | $JSON_PRETTY_PRINT
    echo ""
    echo =========== END RESPONSE : $RESOURCE =========
    echo
    shift
  fi
done

echo

if [ $ARGS -eq 0 ]; then
  echo "Run with one or more of the following argument(s) in order of appearance:"
  echo ""
  echo "Quick start argument sets are:"
  echo ""
  grep "\#\#" $0 | grep "ALIAS" | cut -c 12-
  echo ""
  echo "Step by step arguments are:"
  echo ""
  grep "\#\#" $0 | grep -v "ALIAS" | cut -c 3-
  echo
fi

if [ "$#" -ne 0 ]; then
  echo "Failed to process arguments starting from: $1"
  $0
fi
