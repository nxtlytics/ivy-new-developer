#!/usr/bin/env bash

case $1 in
-h|-h*|--h*)
    echo "$(basename $0) - interactively set up Nexus repositories for Ivy"
    exit 0
    ;;
*)
    ;;
esac

echo "\
This script is used for setting up repository access (Nexus) for new developers working with Ivy tools.

Prior to configuring this, you should have:
1. Access to Nexus over HTTPS
2. Nexus username/password

Before proceeding, please note:
* This script will reconfigure this machine to use the Nexus MAVEN/NPM/PIP/DOCKER repositories.
* Access to these repositories requires VPN access.
* Any custom MAVEN/NPM/PIP configuration on this machine will be OVERWRITTEN.
* In the case of Docker, nexus' docker registry will now be available to you, but you will still
  be able to pull images from public dockerhub

If you don't have the requirements for continuing or want to abort setup, simply press CTRL-C now.
"

# Some variables
NEXUS_HOST="nexus.nxtlytics.com"
NPM_MIRROR_PATH="/repository/npm"
NPM_HOSTED_PATH="/repository/npm-hosted"
PYPI_MIRROR_PATH="/repository/pypi"
PYPI_HOSTED_PATH="/repository/pypi-hosted"
MVN_SERVER_ID="nxtlytics"
MVN_SETTINGS_DIR="${HOME}/.m2"
MVN_SETTINGS_XML="${MVN_SETTINGS_DIR}/settings.xml"
NPM_TEST_PACKAGE="@ivy/cicd-test"
PYPI_TEST_PACKAGE="cicd-test"
DOCKER_HOST="docker.nxtlytics.com"
PIPENV_PACKAGE="git+https://github.com/pypa/pipenv.git@d10b2a216a25623ba9b3e3c4ce4573e0d764c1e4"
TOOL_CHECKS=("pip3" "npm" "mvn" "docker")

# Check if the environment is sane
for TOOL in ${TOOL_CHECKS[@]}; do
    which ${TOOL} 2>&1 >/dev/null
    if [[ $? -ne 0 ]]; then
        echo "Missing \"$TOOL\"! Cannot continue. Please ensure you have the correct tools installed with Brew."
        exit 1
    fi
done

# Check if user is connected to the VPN
ping -c 2 ${NEXUS_HOST} 2>&1 >/dev/null
if [[ $? -ne 0 ]]; then
    echo "Unable to contact Nexus, are you connected to the VPN?"
    exit 1
fi

bold=$(tput bold)
norm=$(tput sgr0)
# Read the username and password
read -p "${bold}G Suite Email (you@nxtlytics.com): ${norm}" USER_EMAIL
read -p "${bold}Nexus Username: ${norm}" NEXUS_USER
read -s -p "${bold}Nexus Password: ${norm}" NEXUS_PASS

echo -e "\n\nLet's confirm that.
    ${bold}Email Address: ${norm} ${USER_EMAIL}
    ${bold}Nexus Username: ${norm} ${NEXUS_USER}
    ${bold}Nexus Password: ${norm} <hidden>\n"

while true; do
    read -p "Everything look good? [yes/no]" yn
    case $yn in
        [Yy]* ) echo "Great"'!'" Let's go."; break;;
        [Nn]* ) echo 'Okay. Sorry to hear. Bye!'; exit 1;;
        * ) echo "Please answer yes or no.";;
    esac
done

###########
# Maven Setup
###########
echo "Setting up Maven..."
test -d "${MVN_SETTINGS_DIR}" || mkdir "${MVN_SETTINGS_DIR}"
if [[ -e "${MVN_SETTINGS_XML}" ]]; then
  python3 mvn.py
else
  echo "<settings>
  <servers>
    <server>
      <id>${MVN_SERVER_ID}</id>
      <username>${NEXUS_USER}</username>
      <password>${NEXUS_PASS}</password>
    </server>
  </servers>
</settings>" > "${MVN_SETTINGS_XML}"
fi

###########
# NPM Setup
###########
echo "Setting up NPM..."
NPM_AUTH=$(echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64)
echo "# Pull-only
registry=https://${NEXUS_HOST}${NPM_MIRROR_PATH}
_auth=${NPM_AUTH}
email=${USER_EMAIL}
always-auth=true

# Scoped registry config
@ivy:registry=https://${NEXUS_HOST}${NPM_HOSTED_PATH}
//${NEXUS_HOST}${NPM_HOSTED_PATH}:_auth=${NPM_AUTH}
//${NEXUS_HOST}${NPM_HOSTED_PATH}:email=${USER_EMAIL}
//${NEXUS_HOST}${NPM_HOSTED_PATH}:always-auth=true" > ~/.npmrc

############
# Pip Setup
############
echo "Setting up Pip/Pipenv/Twine..."
mkdir -p ~/.config/pip
echo "[global]
index = https://${NEXUS_HOST}${PYPI_MIRROR_PATH}/pypi
index-url = https://${NEXUS_HOST}${PYPI_MIRROR_PATH}/simple" > ~/.config/pip/pip.conf
echo "machine ${NEXUS_HOST}
  login ${NEXUS_USER}
  password ${NEXUS_PASS}" > ~/.netrc
chmod 0600 ~/.netrc

# Twine (Pip uploads)
echo "[distutils]
index-servers =
  nexus
[nexus]
repository: https://${NEXUS_HOST}/repository/pypi-hosted/
username: ${NEXUS_USER}
password: ${NEXUS_PASS}" > ~/.pypirc

if ! pipenv --version | grep '2018.11.27.dev0' &> /dev/null; then
  echo "I noticed pipenv is not install or is not using our recommended version"
  echo "I can install/update pipenv for you"
  read -p "Would you want me to? " -n 1 -r
  echo
  if [[ ${REPLY} =~ ^[Yy]$ ]]
  then
      pip3 install ${PIPENV_PACKAGE}
  fi
fi

############
# Docker Setup
############
echo "Setting up Docker"
DOCKER_OUTPUT=$(printf "${NEXUS_PASS}" |  docker login --username ${NEXUS_USER} --password-stdin ${DOCKER_HOST} 2>&1)
DOCKER_STATUS=$?

# All finished, test to make sure everything works
STATUS=0
echo "Testing NPM..."
NPM_OUTPUT=$(npm show ${NPM_TEST_PACKAGE} 2>&1)
if [[ $? -ne 0 ]]; then
    echo "NPM can't find package \"${NPM_TEST_PACKAGE}\"."
    echo -e "Debug output:\n ${NPM_OUTPUT}\n"
    STATUS=1
fi
echo "Testing Pip..."
PIP_OUTPUT=$(pip3 search ${PYPI_TEST_PACKAGE} 2>&1)
if [[ $? -ne 0 ]]; then
    echo "PIP can't find package \"${PYPI_TEST_PACKAGE}\"."
    echo -e "Debug output:\n ${PIP_OUTPUT}\n"
    STATUS=1
fi
echo "Testing Docker..."
if [[ ${DOCKER_STATUS} -ne 0 ]]; then
    echo "Docker was not able to login to \"${DOCKER_HOST}\"."
    echo -e "Debug output:\n ${DOCKER_OUTPUT}\n"
    STATUS=1
fi

echo 'Finished!'
if [[ ${STATUS} -ne 0 ]]; then
    echo "Something didn't quite work right, though. Please check the output listed above and contact someone for assistance"
    exit ${STATUS}
fi
