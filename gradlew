#!/bin/sh

##############################################################################
#
#  Gradle start up script for UN*X
#
##############################################################################

# Attempt to set APP_HOME
APP_HOME=$(dirname "$0")
APP_HOME=$(cd "$APP_HOME" && pwd)

# Add default JVM options here. You can also use JAVA_OPTS and GRADLE_OPTS to pass JVM options to this script.
DEFAULT_JVM_OPTS=""

# Use the maximum available, or set MAX_FD != -1 to use that value.
MAX_FD="maximum"

# Make sure we have a valid JAVA_HOME
if [ -z "$JAVA_HOME" ]; then
  JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
fi

if [ -z "$JAVA_HOME" ]; then
  echo "ERROR: JAVA_HOME is not set and no 'javac' command could be found in your PATH."
  exit 1
fi

GRADLE_JAR="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"

if [ ! -f "$GRADLE_JAR" ]; then
  echo "ERROR: Gradle wrapper JAR not found: $GRADLE_JAR"
  exit 1
fi

exec "$JAVA_HOME/bin/java" $DEFAULT_JVM_OPTS -jar "$GRADLE_JAR" "$@"