#!/bin/bash

#export variables for GOVC
# export GOVC_URL=10.193.134.35
# export GOVC_USERNAME=administrator@vsphere65.local
# export GOVC_PASSWORD=NTJY1sPDXKKu!
# export GOVC_INSECURE=true

#find all hosts
echo "Finding all hosts..."
govc find . -type h | sed 's/.*\///' > hosts.txt

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

    #find newest patch info
    latest=$(head -n 1 builds.txt)

    #split latest into array containing build name in fields[0] and build number in fields[1]
    IFS=',' read -ra fields <<< "$latest"
    echo "Latest patch for ESXi-$version is ${fields[0]} with build number ${fields[1]}"

    #check whether the host needs to be patched
    if [ "$build" -ne "${fields[1]}" ]
    then
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
      echo "Sleeping for 5 minutes while host reboots"
      sleep 5m

      #exit maintenance mode
      echo "Removing $GOVC_HOST from maintenance mode"
      govc host.maintenance.exit "$GOVC_HOST"
    else
      echo "$GOVC_HOST already patched to latest version"
    fi

done < hosts.txt
