# Guidance and framework for running HPC applications on Azure

This repository provides automation scripts for creating [Azure
Batch](https://azure.microsoft.com/services/batch/) pools that you can use to run common high-performance
computing (HPC) applications. This repo also serves as a catalog of HPC
applications that you can use for testing. More than a dozen common
HPC applications are currently supported, including several ANSYS solvers and
Star-CCM+, and you can add more as needed as described in this guide.

**In this guide:**

- [Overview](#overview)
    - [Azure Batch considerations](#azure-batch-considerations)
- [Prerequisites](#prerequisites)
    - [Set up NFS server and network](#set-up-nfs-server-and-virtual-network)
    - [Create site-to-site VPN](#create-site-to-site-vpn)
- [Create Azure resources and
  configuration](#create-azure-resources-and-configuration)
    - [Create a Key Vault to store secrets](#create-a-key-vault-to-store-secrets)
    - [Specify subscription and location](#specify-subscription-and-location)
    - [Get Packer](#get-packer)
    - [Store the images](#store-the-images)
    - [Specify the cluster type](#specify-the-cluster-type)
    - [Identify infrastructure addresses](#identify-infrastructure-addresses)
    - [Set up analytics](#set-up-analytics)
    - [Application storage](#application-storage)
    - [Store results](#store-results)
- [Run application](#run-application)
    - [Set up an HPC application](#set-up-an-hpc-application)
    - [Add an application to the catalog](#add-an-application-to-the-catalog)
    - [Add test cases](#add-test-cases)
    - [MPI environment variables](#mpi-environment-variables)
    - [Log data](#log-data)
- [Collect telemetry data](#collect-telemetry-data)

# Overview

The goal of this repo is to help you set up an environment in Azure
using either [Azure Batch](https://azure.microsoft.com/services/batch/) pools. These compute job scheduling services connect to an HPC application
and run it efficiently on Azure so you can perform tests.

As the following figure shows, this readme describes a three-step approach:

1.  Build an image. The automation scripts use [HashiCorp
    Packer](https://www.packer.io/), an open source tool for creating build
    images. Custom images are stored in separate infrastructure blobs.

2.  Create a Batch pool to automate the creation of the
    compute nodes (virtual machines) used to run your HPC application.

3.  Run the application. Pools of virtual machines are created with a custom
    image on demand. You can optionally set up Azure Log Analytics to collect
    telemetry during the testing.

![architecture](documentation/images/architecture.png)

## Azure Batch considerations

Batch offers clustering as a service that includes an integrated scheduler.
Batch creates and manages a pool of virtual machines , installs the applications
you want to run, and schedules jobs to run on the nodes. You only pay for the
underlying resources consumed, such as the virtual machines, storage, and
networking. 

# Fast start

Before using these scripts, do the following:

1.  It is highly recommended to use [Cloud Shell](https://azure.microsoft.com/en-us/features/cloud-shell/) which is the fastest way to start. 

> Notes:
>
>If you decide to use a centos VM then you will need to 
>- install jq (yum install -y jq)
>- install azure cli and do "az login"
>    - https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
>- install packer (As of this time we recommend that you install 1.2.5)
>    - https://releases.hashicorp.com/packer/1.2.5/
>
>If running Bash on Windows, follow these
>    [instructions](https://www.michaelcrump.net/azure-cli-with-win10-bash/).

2.  Clone the repo:
```
    git clone git@github.com:az-cat/az-hpcapps.git
```

3. Fill up the configuration file by running the setup script
```
    ./setup.sh
```

4.  Install [Batch Explorer](https://github.com/Azure/BatchExplorer) for monitoring and scaling your Azure Batch pools.
   
5.  Now you are ready to start, please jump to [Run application](#run-application)

For details on what is configured see below.

## Set up NFS server and virtual network

A network file system (NFS) server is used as a shared storage for applications
that need to share data across message passing interface (MPI) processes. In the
GitHub repo, the deploy\_nfs.json file builds a virtual network and an NFS
server with a 1 TB data disk.

> **IMPORTANT**: This step is mandatory as virtual machine pools will be created
> within this virtual network.

The virtual network is created with these properties:

-   Default name: `hpcvnet`
-   Address space: `10.0.0.0/20`
-   Subnets:
    -   admin : `10.0.2.0/24`
    -   compute : `10.0.8.0/21`
-   NSG:
    -   admin : Allow SSH and HTTPS inbound connections

The NFS server is created with these properties:

-   Name : `nfsnode`
-   Private IP : `10.0.2.4`
-   Admin : `hpcadmin`
-   SSH Key : `~/.ssh/id_rsa.pub`
-   Data disk : `1 TB` (P30)
-   NFS mount : `/data`

**To set up the NFS server and network:**

1.  Create a resource group to host your virtual network and NFS server if
    needed:

```
    az group create --location <location> --name <resource_group>
```

For Azure Batch, the resource group by default is the one that includes your Batch account. 

2.  Deploy the virtual network and the NFS server.

```
    ./deploy_nfs.sh <config.json> <vnet_name> <resource_group>
```

The admin account created for the NFS server is named **hpcadmin** and your local public SSH key located here will be used for authentication. After the script is run, the full DNS name of the virtual machine is displayed.

## Create site-to-site VPN

If your HPC application needs a license server, make sure it can be accessed
from the virtual machines in the Batch pools. We used
site-to-site VPN to connect the license servers located in the different
subscriptions to the compute and batch resources. We considered using virtual
network peering, but found it impractical in this scenario since it needs
permission from the virtual network owners on both sides of the peering
connection.

We created subnets and gateways across two subscriptions that hosted three
resource groups and three virtual networks. We used a hub-spoke model to connect
the compute and batch resource groups and virtual networks to the ISV License
Server network. The connections were set up bidirectionally to allow for
troubleshooting.

To create a site-to-site VPN or set of site-to-site VPN tunnels between virtual
networks:

1.  Create a virtual network if you do not have one already with its
    corresponding address spaces and subnets. Repeat this again for the
    secondary virtual network and so on. Detailed instructions are located
    [here](https://docs.microsoft.com/azure/vpn-gateway/vpn-gateway-howto-vnet-vnet-resource-manager-portal).

2.  If you already have two or more virtual networks or have completed the
    creation phase above, do the following under each of the virtual networks
    you want to connect together using site-to site-VPNs.

    1.  Create a gateway subnet.

    2.  Specify the DNS server (optional).

    3.  Create a virtual network gateway.

3.  When all the gateways are completed, create your virtual network gateway
    connections [using the Azure
    portal](https://docs.microsoft.com/azure/vpn-gateway/vpn-gateway-howto-vnet-vnet-resource-manager-portal).

**NOTE:** These steps work only for virtual networks in the same subscription.
If your virtual networks are in different subscriptions, you must [use
PowerShell to make the
connection](https://docs.microsoft.com/azure/vpn-gateway/vpn-gateway-vnet-vnet-rm-ps).
However, if your virtual networks are in different resource groups in the *same*
subscription, you can connect them using the portal.

For more information about virtual network peering, see these resources:

-   [General availability: Global VNet
    Peering](https://azure.microsoft.com/updates/global-vnet-peering-general-availability/)
-   [Virtual network peering
    documentation](https://docs.microsoft.com/azure/virtual-network/virtual-network-peering-overview)
-   [Create, change, or delete a virtual
    network](https://docs.microsoft.com/azure/virtual-network/manage-virtual-network)

# Create Azure resources and configuration

All of the scripts used to build an image, create a cluster, and run
applications use the same configuration file, config.json. This file is an Azure
Resource Manager template in JavaScript Object Notation (JSON) format that
defines the resources to deploy. It also defines the dependencies between the
deployed resources. Before running the automation scripts, you must update the
config.json file with your values as explained in the sections below.

**config.json**

```json
{
    "subscription_id": "",
    "location": "",
    "packer": {
        "executable": "/bin/packer",
        "base_image": "baseimage.sh",
        "private_only": "false",
        "vnet_name": "",
        "subnet_name": "",
        "vnet_resource_group":""
    },
    "service_principal": {
        "tenant_id": "",
        "client_id": "",
        "client_secret": "<keyvaultname>.spn-secret"
    },
    "images": {
        "resource_group": "",
        "storage_account": "",
        "name": "centos74",
        "publisher": "OpenLogic",
        "offer": "CentOS-HPC",
        "sku": "7.4",
        "vm_size": "STANDARD_H16R",
        "nodeAgentSKUId": "batch.node.centos 7"
    },
    "cluster_type": "batch",
    "batch": {
        "resource_group": "",
        "account_name": "",
        "storage_account": "",
        "storage_container": "starttasks"
    },
    "infrastructure": {
        "nfsserver": "10.0.2.4",
        "nfsmount": "/data",
        "beegfs": {
            "mgmt":"x.x.x.x",
            "mount":"/beegfs"
        },
        "licserver": "",
        "network": {
            "resource_group": "",
            "vnet": "hpcvnet",
            "subnet": "compute",
            "admin_subnet": "admin"
        },
        "analytics": {
            "workspace":"",
            "key":"<keyvaultname>.analytics-key"
        }
    },
    "appstorage": {
        "resource_group": "",
        "storage_account": "",
        "app_container": "apps",
        "data_container": "data"
    },
    "results": {
        "resource_group": "",
        "storage_account": "",
        "container": "results"
    }
}
```

> **Note**: Secrets have to be stored in a KeyVault, see the section below on how to store your secrets
>

## Create a Key Vault to store secrets
Azure Key Vault is used to store your secret and avoid storing them in configuration files. Configuration fields storing secrets will instead store the keyvault name and the key name using the naming pattern **vault_name.key_name**. If you use the setup.sh script, the Key Vault will be automatically created for you and filled with the required secrets. 

To create a Key Vault use this command :

``` 
az keyvault create --name 'Contoso-Vault2' --resource-group 'ContosoResourceGroup' --location eastus
``` 

To add a secret to Key Vault use this command :

``` 
az keyvault secret set --vault-name 'Contoso-Vault2' --name 'ExamplePassword' --value 'Pa$$w0rd'
``` 

> **Note**: Make sure you are granted read access to the KeyVault Secrets. Check the Access policies of the Key Vault to see if your account is listed there with the read/list access to secrets.
>

To learn more about Key Vault see the online documentation [here](https://docs.microsoft.com/en-us/azure/key-vault/)


## Specify subscription and location

The region where deploy your resources must match the region used by your Batch
account.

Update the following lines in config.json:

```json
{
    "subscription_id": "your subscription id",
    "location": "region where to deploy your resources"
}
```

## Get Packer

You must copy the [Packer](https://www.packer.io/intro/index.html) binary and
add it to the `bin` directory of the repo. Then retrieve the full Packer path
and update the executable value in config.json as follows:

```json
"packer": {
    "executable": "bin/packer",
    "base_image": "baseimage-centos.sh",
    "private_only": "false",
    "vnet_name": "",
    "subnet_name": "",
    "vnet_resource_group":""
}
```

If you don't have one, create a service principal for Packer as follows:

```
az ad sp create-for-rbac --name my-packer
```

Outputs:

```json
{
    "appId": "99999999-9999-9999-9999-999999999999",
    "displayName": "my-packer",
    "name": "http://my-packer",
    "password": "99999999-9999-9999-9999-999999999999",
    "tenant": "99999999-9999-9999-9999-999999999999"
}
```

Using these output values, in config.json, update the values for **tenant_id**,
**client_id**. Store the **client_secret** in your KeyVault under the spn-secret key:

```json
"service_principal": {
    "tenant_id": "tenant",
    "client_id": "appId",
    "client_secret": "<keyvaultname>.spn-secret"
}
```

> By default Packer create a VM with a public IP and use it to SSH in and inject the configuration scripts. If you want to stay in a private network, you need to run the build_image.sh script within that VNET, set **private_only** to **true**, and specify values for **vnet_name**, **subnet_name** and **vnet_resource_group**.


## Store the images

To store the images, create a storage account in the same location as your Batch
account as follows:

```
az group create --location <location> --name my-images-here
az storage account create -n "myimageshere" -g my-images-here --kind StorageV2 -l <location> --sku Standard_LRS
```

Then specify the operating system, virtual machine size, and batch node agent to
be used. You can use the following command to list the agents and operating
systems supported by Azure Batch:

```
az batch pool node-agent-skus list --output table
```

To list the virtual machines sizes available in your region, run this command:

```
az vm list-sizes --location <region> --output table
```

In config.json, update the values in the **images** section:

```json
"images": {
    "resource_group": "my-images-here",
    "storage_account": "myimageshere",
    "name": "centos76",
    "publisher": "OpenLogic",
    "offer": "CentOS-HPC",
    "sku": "7.6",
    "vm_size": "STANDARD_HC44RS",
    "nodeAgentSKUId": "batch.node.centos 7"
}
```

## Specify the cluster type

```
    "cluster_type": "batch",
```

Specify the resource group containing the Batch account,
the name of the Batch account, and the name of the storage account linked to the
Batch account. If you don't have a Batch account, use these
[instructions](https://docs.microsoft.com/azure/batch/batch-account-create-portal)
to create one.

```json
"batch": {
    "resource_group": "batchrg",
    "account_name": "mybatch",
    "storage_account": "mybatchstorage",
    "storage_container": "starttasks"
}
```


## Identify infrastructure addresses

In config.json, you must specify the IP addresses of the NFS server and license
server. If you use the default scripts to build your NFS server, the IP address
is 10.0.2.4. The default mount is **/data**. For the **network** values, specify the **resource_group** name.
The values for **vnet**, **subnet**, and **admin_subnet** are the same as those
used earlier when building the NFS server and virtual network.

> **NOTE:** If you have an Avere system deployed in your network, you can specify its IP and mount point in the NFS settings.

If you have a BeeGFS system setup, you can specify the management IP and the mount point (default is **/beegfs**). By default the client version 7.0 is setup inside the images.

> **NOTE:** See this [repo](https://github.com/paulomarquesc/beegfs-template) for reference on how to deploy BeeGFS on Azure


```json
"infrastructure": {
    "nfsserver": "10.0.2.4",
    "nfsmount": "/data",
    "beegfs": {
        "mgmt":"x.x.x.x",
        "mount":"/beegfs"
    },
    "licserver": "w.x.y.z",
    "network": {
        "resource_group": "batchrg",
        "vnet": "hpcvnet",
        "subnet": "compute",
        "admin_subnet": "admin"
    }
}
```

## Set up analytics

If you want to store the telemetry data collected during the runs,
you can create an Azure [Log Analytics
workspace](https://docs.microsoft.com/azure/log-analytics/log-analytics-quick-create-workspace).
Once in place, update config.json and specify the Log Analytics workspace ID. Store the application key from your environment in KeyVault under **analytics-key** :

```json
"analytics": {
    "workspace":"99999999-9999-9999-9999-999999999999",
    "key":"<keyvaultname>.analytics-key"
}
```

The key can be find in the Advanced Settings / Connected sources of your workspace.

## Application storage

Application packages are stored in an Azure Storage account that uses one
container for the HPC application binaries and one container for the test
cases. Each HPC application is listed in a subfolder of the **apps** folder that
contains both binaries and data. Many applications are already included in the
repo, but if you do not see the one you want, you can add one as described
[later](#add-an-application-to-the-catalog) in this guide.

In config.json, update the following:

```json
"appstorage": {
    "resource_group": "myappstore resource group",
    "storage_account": "myappstore",
    "app_container": "apps",
    "data_container": "data"
}
```

## Store results

Application outputs and logs are automatically stored inside blobs within the
Storage account and container specified in config.json. Specify the location for
your results as follows:

```json
"results": {
    "resource_group": "myresults resource group",
    "storage_account": "myresults",
    "container": "results"
}
```

# Run application

To run a specific HPC application, do the following:

1.  Build an image for that application by running the following script,
    replacing **app-name** with the value documented in the table below:

```
    ./build_image.sh -a app-name
```

2.  Create a virtual machine pool for Batch running the following script, replacing **app-name** with the value documented in the [table](#set-up-an-hpc-application) below:

```
    ./create_cluster.sh -a app-name
```

3.  After the Azure Batch pool is created, scale it to the number of nodes you
    want to run on. To scale a
    pool, use Azure portal or [Batch Explorer](https://github.com/Azure/BatchExplorer).

4.  Run the HPC application you want as the following section
    describes.

```
    ./run_app.sh -a app-name \
            -c config -s script \
            -n nodes -p process_per_node \
            -x script_options
```


## Set up an HPC application 

Instructions for setting up, running, and analyzing results for the following
HPC applications are included in this repo, and more are being added. If the
application you want is not shown here, see the next section.

| **Application**                                                          | **app-name**       | **Versions**   | **Shared FS** | **Licence** |
|--------------------------------------------------------------------------|--------------------|----------------|---------------|-------------|
| [Abaqus](./documentation/apps/abaqus.md)                                 | abaqus             | 2017           |    No         |  Yes        |
| [ANSYS Mechanical](./documentation/apps/mechanical.md)                   | mechanical         | 19.2           |    No         |  Yes        |
| [ANSYS Fluent](./documentation/apps/fluent.md)                           | fluent             | 19.2           |    No         |  Yes        |
| [Builder](./documentation/apps/builder.md) - *build scripts*             | builder            |                |    No         |  No         |
| [Empty](./documentation/apps/empty.md) - *diagnostics*                   | empty              |                |    No         |  No         |
| [Gromacs](./documentation/apps/gromacs.md)                               | gromacs            | 2018.1         |    Yes        |  No         |
| [Linpack](./documentation/apps/empty.md)                                 | empty              | 2.3            |    No         |  No         |
| [NAMD](./documentation/apps/namd.md)                                     | namd               | 2.10           |    No         |  No         |
| [nwchem](./documentation/apps/nwchem.md)                                 | nwchem             | 6.8            |    Yes        |  No         |
| [OpenFOAM](./documentation/apps/openfoam.md)                             | openfoam           | 4.x            |    Yes        |  No         |
| [Pamcrash](./documentation/apps/pamcrash.md)                             | pamcrash           | 2017 2018      |    No         |  Yes        |
| [Quantum Espresso](./documentation/apps/qe.md)                           | qe                 | 6.3            |    Yes        |  No         |

## Add an application to the catalog

Many common HPC applications are included in the repo’s catalog in the **apps**
folder. To add an application to the catalog:

1.  Under **apps**, create a new folder with the name of the application. Use
    only the lowercase letters *a* to *z*. Do not include numbers, special
    characters, or capital letters.

2.  Add a file to the folder called `install_<app-name>.sh`. The folder name
    must match the name used by `create_image.sh` to call
    `install_<app-name>.sh`.

3.  In the new `install_<app-name>.sh` file, add steps to copy the executables
    for the application and include any required installation dependencies.

    -   Our convention is to install in /opt, but anywhere other than the home
        directories or ephemeral disk will work.

    -   Pull the binaries from the Azure storage account specified in
        config.json as the `.appstorage.storage.account` property.

    -   Specify the container used for `.appstorage.app.container`.

4.  Add the following lines to your `install_<app-name>.sh` script to get the
    storage endpoint and SAS key:

```
    HPC_APPS_STORAGE_ENDPOINT="#HPC_APPS_STORAGE_ENDPOINT#"
    HPC_APPS_SASKEY="#HPC_APPS_SASKEY#"
```

> **NOTE:** The `build_image.sh` script replaces `#HPC_APPS_STORAGE_ENDPOINT#`
> and `#HPC_APPS_SASKEY#` in the install file before it is used.

After you add a new application script, use the steps provided earlier to run it. That is, build the image, create the pools or clusters, then run
the application. Make sure the value of **<app_name>** in the commands (such as
`install_<app_name>`) exactly matches the name you used.

## Add test cases

New tests cases must be added to their **app** folder and called
`run_<CASE-NAME>.sh`. This script is run after all the resources are ready. The
following environment variables are available to use:

| **Variable**         | **Description**                                     |
|----------------------|-----------------------------------------------------|
| ANALYTICS_WORKSPACE  | Log Analytics workspace ID                          |
| ANALYTICS_KEY        | Log Analytics key                                   |
| APPLICATION          | Application name                                    |
| APP_PACKAGE_DIR      | Application package dir when using Batch Packages   |
| CORES                | Number of MPI ranks                                 |
| HPC_APPS_STORAGE_ENDPOINT | Application packages storage endpoint          |
| HPC_APPS_SAS_KEY     | Application packages key                            |
| HPC_DATA_SAS_KEY     | Application data SAS key                            |
| HPC_DATA_STORAGE_ENDPOINT | Application data endpoint                      |
| IB_PKEY              | Infiniband primary key                              |
| INTERCONNECT         | Type of interconnect (**tcp**, **ib** or **sriov**) |
| LICENSE_SERVER       | Hostname/IP address of the license server           |
| MPI_HOSTFILE         | File containing an MPI hostfile                     |
| MPI_HOSTLIST         | A comma-separated list of hosts                     |
| MPI_MACHINEFILE      | File containing an MPI machinefile                  |
| NODES                | Number of nodes for the task                        |
| OUTPUT_DIR           | Directory for output that is uploaded               |
| PPN                  | Number of processes per node to use                 |
| SHARED_DIR           | Path to shared directory accessible by all nodes    |
| UCX_IB_PKEY          | Infiniband primary key for UCX                      |
| VMSIZE               | VM sku name in lower case (standard_h16r)           |

## MPI environment variables

The creator of the script is responsible for setting up the MPI environment in
addition to specifying all the MPI flags.

### Intel MPI
To set up the MPI environment, run:

```
source /opt/intel/impi/*/bin64/mpivars.sh
```

> **NOTE:** The wildcard is used here to avoid issues if the Intel MPI version
> changes.

The mandatory environment variables when using Azure with **H16r only**, are **I_MPI_FABRICS**,
**I_MPI_DAPL_PROVIDER** and **I_MPI_DYNAMIC_CONNECTION**. We also recommend using
**I_MPI_DAPL_TRANSLATION_CACHE** because some applications crash if it is not
set. The environment variables can be passed to **mpirun** with the following
arguments:

```
-genv I_MPI_FABRICS shm:dapl
-genv I_MPI_DAPL_PROVIDER ofa-v2-ib0
-genv I_MPI_DYNAMIC_CONNECTION 0
-genv I_MPI_DAPL_TRANSLATION_CACHE 0
```

When using **HB** or **HC** use these settings :

```
-genv I_MPI_FABRICS shm:ofa
-genv I_MPI_DYNAMIC_CONNECTION 0
```

### Platform MPI

Download the Platform MPI installation package **platform_mpi-09.01.04.03r-ce.bin** from https://www.ibm.com/developerworks/downloads/im/mpi/index.html, and upload it in your APPS (.appstorage.storage_account) storage account inside the virtual directory **apps/platformmpi-941** 



## Log data

The application run script uploads any data in **OUTPUT_DIR** to the results
storage account. Additionally, any JSON data that is stored in
**$APPLICATION.json** when the script exits is uploaded to Log Analytics. This
information includes run time or iterations per second, and can be used to track
the application performance. Ideally this data can be extracted from the program
output, but the following simple example shows a timing metric for **mpirun**:

```
start_time=$SECONDS
mpirun ...insert parameters here...
end_time=$SECONDS
# write telemetry data
cat <<EOF >$APPLICATION.json
{
"clock_time": "$(($end_time - $start_time))"
}
EOF
```

# Collect telemetry data

For each application, you can collect and push key performance indicators (KPI)
into Log Analytics. To do so, each application run script needs to build an
**$APPLICATION.json** file as explained in the previous section. You should extract
from the application logs and outputs the data needed to compare application
performance, like Wall Clock Time, CPU Time, iterations, and any ranking
metrics.

In addition to application-specific data, the Azure metadata service and the
execution framework also collect node configuration data (virtual machine size,
series), Azure running context (location, batch account, and so on.), and the
number of cores and processes per nodes.

# Upcoming applications

The application catalog is growing regularly. Below is the list of what is currently in our pipeline:

- Ansys CFX
- Converge CFD
- GAMMES
- LAMMPS
- StarCCM

To request other applications, send us a note as an issue in the repo.

