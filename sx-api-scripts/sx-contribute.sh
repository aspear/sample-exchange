#!/bin/bash

#------------------------------------------------------------------------------
# Author: Aaron Spear aspear@vmware.com
# This is a script that shows to how manually use the VMware Sample Exchange API
# to create a sample.  You can get more information on the API at
# https://code.vmware.com/apis/47/sample-exchange
#

# set -x

ESP_AUTH_BASE_URL="https://auth.esp.vmware.com/api/auth/v1"
VCODE_SERVICES_BASE_URL=${VCODE_SERVICES_BASE_URL:-"https://apigw.vmware.com/sampleExchange/v1"}

#------------------------------------------------------------------------------
# AUTHORIZATION USING ESP SERVICES
if [ -z "${VCODE_TOKEN}" ]; then

    # there is no VCODE_TOKEN defined, so we are assuming we are using MyVMware user name and password.
	if [ -z "${MYVMWARE_EMAIL}" ]; then
		echo "usage: VCODE_TOKEN for apikey, or MYVMWARE_EMAIL and MYVMWARE_PASSWD env variables must contain your MyVMware email and password."
		exit 1;
	fi

	if [ -z "${MYVMWARE_PASSWD}" ]; then
		echo "usage: VCODE_TOKEN for apikey, or MYVMWARE_EMAIL and MYVMWARE_PASSWD env variables must contain your MyVMware email and password."
		exit 1;
	fi

	echo "Getting access token from MyVMware credentials (MYVMWARE_EMAIL and MYVMWARE_PASSWD env variables)"

    ACCESS_TOKEN=`curl -s "${ESP_AUTH_BASE_URL}/tokens" \
         -H  "accept: application/json" \
         -H  "Content-Type: application/json" \
        -d "{  \"grant_type\": \"password\",  \"provider\":\"myvmware\", \"username\": \"${MYVMWARE_EMAIL}\", \"password\": \"${MYVMWARE_PASSWD}\"}" | sed -n -e 's/.*access_token":"\([^"=]*\)=*".*/\1/p'`
else
   # curl -X POST -d "{'grant_type': 'client_credentials', 'client_id' : 'vsphere_monitor, 'client_secret': 'xxxxx''}" https://<auth-server>/auth/token
   echo "Getting access token for VCODE_TOKEN..."
   ACCESS_TOKEN=`curl -s -X POST "${ESP_AUTH_BASE_URL}/api-tokens/authorize" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "token=${APIV_TOKEN}" \
      | sed -n -e 's/.*access_token":"\([^"=]*\)=*".*/\1/p'`
fi

if [ -z "$ACCESS_TOKEN" ]; then
   echo "Invalid credentials, unable to get access token."
   exit 1
fi

#------------------------------------------------------------------------------
# call the contribution API so start an asynchronous sample contribution
# see https://code.vmware.com/apis/47/sample-exchange#/contributions/createContributionAsync
# which returns a "SampleJob".  The only value that we care about is the id of the new
# sample.

SAMPLE_TAG="Flows"
SAMPLE_NAME="Find out if flows are being dropped requiring firewall changes."
SAMPLE_DESCRIPTION="Find out flows that are being dropped by an application after it has been microsegmented and check if the firewall rule needs an update (legitimate flows being dropped) or if these flows are meant to be dropped."
SAMPLE_PRODUCT="vRealize Operations Manager"

SAMPLE_BODY="flows where firewall ruleid = <ruleid> and Application = <app-name> and firewall action = 'DENY'"

cat > contribution.json <<EOF
{
  "name": "${SAMPLE_NAME}",
  "type": "SNIPPET",
  "readmeHtml": "${SAMPLE_DESCRIPTION}",
  "appendRepositoryReadme": false,
  "repositoryReadmeHtml": "",
  "files": [
    {
      "name": "sample.txt",
      "content": "${SAMPLE_BODY}"
    }
  ],
  "categories": [
    {
      "type": "product",
      "name": "${SAMPLE_PRODUCT}"
    }
  ],
  "tags": [
    {
      "category": "Tags",
      "name": "${SAMPLE_TAG}"
    }
  ],
  "ossLicense": "MIT"
}"
EOF

echo "Queueing sample contribution"
SAMPLE_JOB_JSON=`curl -s -X POST --insecure \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --data @contribution.json \
"${VCODE_SERVICES_BASE_URL}/sampleExchange/v1/contributions/async"`
RETURNVAL=$?
if [ $RETURNVAL -ne 0 ]; then
    echo "Failed to contribute sample, curl returned $RETURNVAL"
    exit 1
fi

rm contribution.json

# extract the job id string from the SampleJob JSON
JOB_ID=`echo "${SAMPLE_JOB_JSON}" | sed -n -e 's/^.*"id"[ ]*:[ ]*\([0-9]*\).*$/\1/p'`

if [ -z "$JOB_ID" ]; then
    echo "ERROR unable to extract id from: ${SAMPLE_JOB_JSON}
    exit 1;
fi

#------------------------------------------------------------------------------
# Utility functions

# You must pass your job string id as the parameter to this
function poll_for_sample_completion() {
   JOB_ID=${1}
   JOB_STATUS_URL="${VCODE_SERVICES_BASE_URL}/sampleExchange/v1/contributions/async/${JOB_ID}"
    SUCCESSFUL_JOB="false"
    COUNTER=0
    while [[ $((COUNTER++)) -lt 40 ]]
    do
        SAMPLE_JOB_JSON=`curl --insecure -s -S -X GET --header "Authorization: Bearer ${ACCESS_TOKEN}" ${JOB_STATUS_URL}`
		# some code to extract the http status as the returned value if the call fails
		if [[ $SAMPLE_JOB_JSON = *"state"* ]]; then
		  STATE=`echo $SAMPLE_JOB_JSON | sed -n -e 's/.*state"[ ]*:[ ]*"\([^"=]*\)=*".*/\1/p'`
          ERROR=`echo $SAMPLE_JOB_JSON | sed -n -e 's/.*error"[ ]*:[ ]*"\([^"=]*\)=*".*/\1/p'`
		else
		    echo "ERROR, SampleJob JSON seems corrupted: $SAMPLE_JOB_JSON";
		    exit 1;
		fi

        if [ "${STATE}" == "FINISHED" ]; then
           # if there is an 'error' string, then there was a problem and this string contains info on what the issue is.
           # otherwise it is successful.
           if [ ! -z "${ERROR}" ]; then
              echo "ERROR contributing sample: ${ERROR}"
              exit 1;
           fi
           echo " Contribution Complete.";
           SUCCESSFUL_JOB="true";
           break;
        else
            printf "."
            sleep 1;
        fi
    done
    if [ "$SUCCESSFUL_JOB" != "true" ] ; then
       echo "ERROR Timed out waiting for ${JOB_STATUS_URL} to return FINISHED or ERROR";
       exit 1;
    fi

    SAMPLE_ID=`echo $SAMPLE_JOB_JSON | sed -n -e 's/.*sampleId"[ ]*:[ ]*\([0-9]*\).*/\1/p'`;

    echo "Created sample https://code.vmware.com/samples/${SAMPLE_ID}";
}

echo "Polling for job ${JOB_ID} completion...";
poll_for_sample_completion ${JOB_ID};

#------------------------------------------------------------------------------
echo "DONE."
