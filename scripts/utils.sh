#!/bin/bash

#########################################################
# Utilities to check things out:
#########################################################

#########################################################
# check cdsw status
#########################################################

check_cdsw(){
  echo "Checking CDSW status (for 10 min max)"
  counter=0
  while [ $counter -lt 600 ]; do

    STATUS_CHECK=`cdsw status | tail -1`
    if [ "$STATUS_CHECK" != 'Cloudera Data Science Workbench is ready!' ]; then
      echo "CDSW Status --> "$STATUS_CHECK
      echo "sleeping for 20s"
      echo;
      sleep 20s
      let counter=counter+20
    else
      echo "CDSW is ready!!!!"
      return
    fi
  done
  echo "CDSW is not ready after 10 minutes.  Exiting...";
  return

}

#########################################################
# check the role state from api
#########################################################

check_role_state(){
  echo "Checking CDSW role state (for 5 min max)"
  counter=0
  while [ $counter -lt 300 ]; do
    CDSW_ROLE_STATE=`curl -u "admin:admin" -k -s GET http://$PRIVATE_IP:7180/api/v19/clusters/Edge2AI/services/cdsw/roles | jq -r '.items[0].roleState'`

    if [ "$CDSW_ROLE_STATE" != 'STOPPED' ]; then
       echo "CDSW Status --> "$CDSW_ROLE_STATE
       echo "sleeping for 20s"
       echo;
       sleep 20s
       let counter=counter+20
    else
       echo "CDSW is STOPPED"
       return
    fi
  done
  echo "CDSW did not stop after 5 minutes.  Exiting...";
  return


}
