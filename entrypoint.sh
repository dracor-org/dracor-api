#!/bin/bash

SAXON="java ${JAVA_OPTIONS} -jar ${SAXON_JAR} env=${EXIST_ENV} context_path=${EXIST_CONTEXT_PATH} default_app_path=${EXIST_DEFAULT_APP_PATH} -xsl:${EXIST_HOME}/adjust-conf-files.xsl"

function adjust_config_files {
# remove DTD references since these were causing troubles
sed -i '2,3d' ${EXIST_HOME}/etc/jetty/webapps/exist-webapp-context.xml
sed -i '2d' ${EXIST_HOME}/etc/jetty/jetty.xml

${SAXON} -s:${EXIST_HOME}/etc/conf.xml -o:/tmp/conf.xml
${SAXON} -s:${EXIST_HOME}/etc/jetty/webapps/exist-webapp-context.xml -o:/tmp/exist-webapp-context.xml
${SAXON} -s:${EXIST_HOME}/etc/webapp/WEB-INF/controller-config.xml -o:/tmp/controller-config.xml
${SAXON} -s:${EXIST_HOME}/etc/webapp/WEB-INF/web.xml -o:/tmp/web.xml
${SAXON} -s:${EXIST_HOME}/etc/jetty/jetty.xml -o:/tmp/jetty.xml

# copying modified configuration files from tmp folder to original destination
mv /tmp/conf.xml ${EXIST_HOME}/etc/conf.xml
mv /tmp/exist-webapp-context.xml ${EXIST_HOME}/etc/jetty/webapps/exist-webapp-context.xml
mv /tmp/controller-config.xml ${EXIST_HOME}/etc/webapp/WEB-INF/controller-config.xml
mv /tmp/web.xml ${EXIST_HOME}/etc/webapp/WEB-INF/web.xml
mv /tmp/jetty.xml ${EXIST_HOME}/etc/jetty/jetty.xml
}

function set_passwd {
${EXIST_HOME}/bin/client.sh -l -s -u admin -P "" << EOF
passwd admin
$1
$1
quit
EOF
echo "do not delete" > ${EXIST_DATA_DIR}/.docker_secret
}

adjust_config_files

# now we are setting the admin password
# if the magic file ${EXIST_DATA_DIR}/.docker_secret exists
# we won't take any action because the password is already set
if [[ -s ${EXIST_DATA_DIR}/.docker_secret ]]
then
    echo "********************"
    echo "password already set"
    echo "********************"

# next, try to read the admin password from Docker secrets
# if the ${EXIST_PASSWORD_FILE} environment variable is set.
elif [[ -s ${EXIST_PASSWORD_FILE} ]]
then
    SECRET=`cat ${EXIST_PASSWORD_FILE}`
    echo "************************************"
    echo "setting password from Docker secrets"
    echo "************************************"
    # setting the eXist admin password
    set_passwd ${SECRET}

# next, look for the ${EXIST_PASSWORD} environment variable
# to set the password
elif [[ ${EXIST_PASSWORD} ]] && ! [[ -s ${EXIST_DATA_DIR}/.docker_secret ]]
then
    # read the password from the environment variable ${EXIST_PASSWORD}
    echo "*************************************************"
    echo "setting password from Docker environment variable"
    echo "NB: this is less secure than via Docker secrets"
    echo "*************************************************"
    # setting the eXist admin password
    set_passwd ${EXIST_PASSWORD}

# finally fallback to generating a random password
else
    # generate a random password and output it to the logs
    SECRET=`pwgen 24 -csn`
    echo "********************************"
    echo "no admin password provided"
    echo "setting password to ${SECRET}"
    echo "********************************"
    # setting the eXist admin password
    set_passwd ${SECRET}
fi

# starting the database
exec ${EXIST_HOME}/bin/startup.sh
