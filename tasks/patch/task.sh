#!/bin/bash

#find all hosts
echo "Finding all hosts..."

if [ -z $CLUSTER_NAME ]
then
  govc find . -type h | sed 's/.*\///' > hosts.txt
else
  govc find $(govc find . -type c -name $CLUSTER_NAME) -type h | sed 's/.*\///' > hosts.txt
fi

echo "Hosts to be patched are"
cat hosts.txt

while read host; do
  export GOVC_HOST=$host

  #Grab current host build and version info
  build=$(govc host.info -json | jq -r '.HostSystems[0].Summary.Config.Product.FullName' | sed 's/.*-//')
  echo "Current build on $GOVC_HOST is $build"
  version=$(govc about -json | jq -r .About.Version)
  echo "Current ESXi version on $GOVC_HOST is $version"

  # scrape updates page for list of build numbers
  echo "Retrieving patch information from https://esxi-patches.v-front.de/ESXi-$version.html"
  curl -X GET "https://esxi-patches.v-front.de/ESXi-$version.html" --referer https://esxi-patches.v-front.de/ \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: text/html" 2>&1 \
    | sed -e $'s/<[^>]*>/ /g' \
    | sed -e $'s/ESXi-*/\\\n&/g' \
    | sed -e $'s/includes/\\\n/g' \
    | grep ESXi- \
    | sed -e $'s/   (Build /,/g' \
    | sed -e $'s/)//g' \
    | sed -e $'s/is the GA release of//g' \
    > builds.txt


    if [ -z $BUILD_NUMBER ]
    then
      #grab latest build
      build_to_use=$(head -n 1 builds.txt)
      echo "Latest patch for ESXi-$version is ${fields[0]} with build number ${fields[1]}"
    else
      while read build_line; do
        IFS=',' read -ra fields <<< "$build_line"
        if [ "$BUILD_NUMBER" -eq "${fields[1]}" ]
        then
          build_to_use=$build_line
        fi
      done < builds.txt

      if [ -z $build_to_use ]
      then
        echo "Build number $BUILD_NUMBER is not valid"
        exit 1
      fi
    fi

    echo "Using build $build_to_use"

    #parse build info
    IFS=',' read -ra fields <<< "$build_to_use"


    #check whether the host needs to be patched
    if [ $build -lt ${fields[1]} ]
    then
      echo "Starting to patch $GOVC_HOST from $build to ${fields[1]}"
      #enter maintenance mode
      echo "Putting $GOVC_HOST into maintenance mode"
      govc host.maintenance.enter "$GOVC_HOST"

      #open external http access
      echo "Opening outbound HTTP access on $GOVC_HOST"
      govc host.esxcli network firewall ruleset set -e true -r httpClient

      #run update
      echo "Updating $GOVC_HOST to ${fields[0]}"
      govc host.esxcli software profile update \
        -p ${fields[0]} \
        -d https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml

      #close external http access
      echo "Closing outbound HTTP access on $GOVC_HOST"
      govc host.esxcli network firewall ruleset set -e false -r httpClient

      #reboot host
      echo "Rebooting $GOVC_HOST"
      govc host.shutdown -r "$GOVC_HOST"

      #wait for the reboot
      #Should this be configurable?
      echo "Sleeping for 5 minutes while host reboots"
      sleep 5m

      #exit maintenance mode
      echo "Removing $GOVC_HOST from maintenance mode"
      output=$(govc host.maintenance.exit "$GOVC_HOST" | grep "An error occurred while communicating with the remote host.")

      #While the output shows that the host is still rebooting, keep trying to bring it out of maintenance mode
      while [ -n "$output" ]
      do
        echo "Sleeping for 2 more minutes while host reboots"
        sleep 2m
        output=$(govc host.maintenance.exit "$GOVC_HOST" | grep "An error occurred while communicating with the remote host.")
      done

      #verify that it successfully came out of maintenance mode, if not exit for manual intervention
      in_maintenance=$(govc host.info -json | jq -r '.HostSystems[0].Summary.Runtime.InMaintenanceMode')
      if [ $in_maintenance == true ]
      then
        echo "$GOVC_HOST is not coming out of maintenance mode"
        exit 1
      fi

      echo "Host $GOVC_HOST successfully patched"
    else
      echo "$GOVC_HOST already patched"
    fi

done < hosts.txt
