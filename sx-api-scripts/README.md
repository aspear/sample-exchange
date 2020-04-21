# Sample Exchange API sample
Example shell script that uses curl to manually call VMware Sample Exchange APIs
to add a sample to the VMware Sample Exchange, https://code.vmware.com/samples .  The script authenticates the
current user (see below), queues a sample contribution and then polls the API for
completion of the contribution printing the resulting URL.

## Authentication
The script requires _authentication_ via one of a couple of mechanisms:

* You can provide your MyVMware password via the MYVMWARE_EMAIL and MYVMWARE_PASSWD environment variables.  You can create a login at https://my.vmware.com .
* You can provide an VMware Extensible Services Platform (ESP) auth API key that you create at https://auth.esp.vmware.com/api-tokens/apiTokens . Put the key value in a VCODE_TOKEN env variable.

## API Reference
You can see the Sample Exchange API at https://code.vmware.com/apis/47/sample-exchange
