# mongo-helm-oci-backup-tool
backup mongo DB dump to OCI object storage

Modified Dockerfile, backup.sh script


I have added logic to upload mongo dumps backup to OCI Object storage - 
> oci os object put -ns \<namespace> -bn \<bucketName> --file \<fileName> 

Requirement:
## Important - Use the same version of mongo running in your cluster (Update the same in Dockerfile)[Dockerfile](Dockerfile) using mongo:4.2.7-enterprise
## OCI-CLI (files: config, private key)
 ### Configure an OCI-CLI environment
The OCI-CLI environment must be activated and configured for use. This includes creating an appropriate OCI configuration file and populating that file with information about the target OCI account.

1. Open a terminal window and change directory to the location of the Oracle OCI scripts. Activate the OCI command line interface.
For example, in Windows:

> cd \<OCI install root>\lib\oracle-cli\Scripts
activate

	On success, (oracle-cli) is added to the command prompt.
In macOS:
> cd ~/lib/oracle-cli/bin
source activate

2. Run the oci setup keys command to create a set of required keys and upload them to your OCI account:
> oci setup keys

On success, a set of keys is generated in the ~/.oci subdirectory. You can verify that they were created by listing the files in the directory. It should contain the files oci_api_key.pem and oci_api_key_public.pem.
3. Upload the keys to the Oracle Cloud Instance:
 - Sign in to the Oracle OCI Cloud Console.
 - To upload the keys as the user you're currently signed-in as, click your username in the top-right corner of the console, then click User Settings.If you're an administrator doing this for another user, click Identity, click Users, and then select the user from the list.

 - Select Resources > API Keys.
 - In the API Keys pane, click Add APIKey.
 - Select Paste Public Key.
 - Paste the value of the OCI public key PEM file and click Add.
4. Create and populate the required OCI Configuration file. To populate the OCI configuration, you must have your region code, your tenancy OCID, and your user OCID.
 - At the command line, execute:
> oci setup config

 - Return to the OCI console and determine the user OCID in one of the following ways:
 If you're the user, open the Profile menu (User menu icon) and click User Settings. 
 If you're an administrator doing this on behalf of another user, navigate to Identity and click Users. The select the user from the list.

 - Copy the user OCID and return to the command line.
 - Paste the user OCID at the User OCID prompt
 - Return to the OCI console and navigate to Administration > Tenancy Details.
 - In the Tenancy Information tab, click Copy to copy the OCID.
 - Return to the command line and paste the value at the OICD prompt and hit return.
 - Return to the OCI console and examine the Region.
 - Return to the command line and enter the associated region. See [Regions and availability domains](https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm "Regions and availability domains").
 - Generate or enter the path to the private PEM file. For example, 
>~/.oci/oci_api_key.pem
 - If required, enter the passphrase used with the key.
 - Enter y or no to the prompt asking about whether to store the passphrase.
 - Okta recommends that you don't store the passphrase. 

## config Steps:
1. Copy following files contents to current directory from ~/.oci/Config to oci-secret and ~/.oci/oci_api_key.pem(private generated above) to ocikey
2. Set secrets in OCI k8s cluster:
example: 
> kubectl --context jayanth.sagar-dev-k8s-cluster -n develop-sts create secret generic mongo-oci-credentials --from-file=credentials=oci-secret
> kubectl --context jayanth.sagar-dev-k8s-cluster -n develop-sts create secret generic oickey --from-file=pemkey=ocikey
3. Run helm install to set cronjob for daily backups.
> helm upgrade --install dev-mongo-backup . --set mongoaddr=mongo-cluster-headless.develop-sts.svc:6362 --set bucket=dev-mongo-backups --set namespace=smartcloud --set database="" --set cloudProvider=oci --set secretName=mongo-oci-credentials --set keyName=ocikey --set jobSchedule="0 */12 * * *" --namespace develop-sts  --kubeconfig ~/.kube/config --kube-context jayanth.sagar-dev-k8s-cluster
4. To perform a current DB backup.
> kubectl --context jayanth.sagar-dev-k8s-cluster -n develop-sts create job --from=cronjob/dev-mongo-backup-job mongo-hot-backup
Cronjob runs once for every 12hours, if we want to collect backup at the moment then use above command 
5. check the cronjob
> kubectl --context jayanth.sagar-dev-k8s-cluster -n develop-sts get cronjob
6. check running jobs
> kubectl --context jayanth.sagar-dev-k8s-cluster -n develop-sts get job


Documentation:
https://developer.oracle.com/learn/technical-articles/oci-cli
https://docs.oracle.com/en-us/iaas/tools/oci-cli/3.20.2/oci_cli_docs/cmdref/os/object/put.html#cmdoption-bucket-name
