#!/bin/bash
##Get and Process Args, Retrieve API password
usage() { echo "Usage: $0" 1>&2; exit 1; }
while getopts ":u:m:" opt; do
  case $opt in
    u) op5user=$OPTARG;;
    m) master=$OPTARG;;   
    *) usage;;
   esac
done
shift $((OPTIND-1))
if [ -z $op5user ] || [ -z $master ] ; then
    usage
    exit 1
fi
echo "OP5 API User Password:"
stty_orig=$(stty -g) # save original terminal setting.
stty -echo           # turn-off echoing.
IFS= read -r passwd  # read the password
stty "$stty_orig"    # restore terminal setting.
authstr=$(echo -n $op5user":"$passwd | base64)
##Create Limit and Offset to get around PHP limits​
limit=500
offset=0

##Get total count of hosts in OP5
totalhost=$(curl -k -s --request GET \
  --url "https://$master:443/api/filter/count?query=%5Bhosts%5D%20all" \
  --header "Authorization: Basic $authstr" )

let totalhost=$(echo $totalhost | grep 'count' | cut -d: -f2 | sed 's/}//g')

##Run with offset if $totalhost > $limit
while [[ $offset -le $totalhost ]]; do
    ##Get all duplicate hosts into a single file
    if [[ $offset == 0 ]]; then
        limoff="limit=$limit"
    else
        limoff="limit=$limit&offset=$offset"
    fi
    ##API call
    allhosts=$(curl -k -s --request GET \
    --url "https://$master:443/api/filter/query?columns=name%2Caddress&$limoff&query=%5Bhosts%5D%20all" \
    --header "Authorization: Basic $authstr" \
    --header 'accept: application/json')
    ##Loop and Filter for duplicates. Only write host with IP as name to file.
    for i in `echo $allhosts | sed 's/\]//g' | sed 's/\[//g' |  sed 's/}\,{/\n/g'`; \
        do 
        i=$(echo $i | sed 's/{//g' | sed 's/}//g')
        if [[ $(echo $allhosts | grep -o $(echo $i | awk -F'[,:]' '{print $4}') 2>/dev/null | wc -l) > 1 && \
        $(echo $i | awk -F'[,:]' '{print $2}') == $(echo $i | awk -F'[,:]' '{print $4}') ]]; \
        then echo $i | sed 's/{//g' >> /tmp/duplicateHosts.txt; fi ; done
    let offset=$offset+$limit
done


##Loop through duplicate hosts and submit API call to remove the host with ip address as name
while read j;
do echo "Removing Host: $(echo $j | awk -F'"' '{print $4}')";
curl -k -s --request DELETE \
  --url "https://$master:443/api/config/host/$(echo $j | awk -F'"' '{print $4}')?format=json" \
  --header 'Accept: application/json' \
  --header "Authorization: Basic $authstr" >/dev/null
done < /tmp/duplicateHosts.txt
##Commit changes
curl -k -s --request POST \
  --url "https://$master:443/api/config/change?format=json" \
  --header "Authorization: Basic $authstr"
##Remove temporary file
rm -f /tmp/duplicateHosts.txt
