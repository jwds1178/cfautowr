# cfautowr - CloudFlare Under Attack Mode Automation

### What does it do
Enables a queue-all Waiting Room with Cloudflare based on CPU load percentage using the Cloudflare API.

### Why
This script will enable it under high CPU load which is indicative of a DDOS attack.  Visitors will queue-up in the Waiting Room while enabled, and automatically be directed on-through to the site once disabled.

### Warning
This is a beta script and I barely know what I'm doing so test this thoroughly before using.

### How?
It creates a service that runs on a timer, which executes our main shell script which gets the current Waiting Room status and checks the CPU usage.  If CPU usage is above our defined limit, it uses the CloudFlare API to set enable the Waiting Room.  If CPU usage normalizes and the time limit has passed, it will disable/suspend the Waiting Room.

### How to install

Navigate to the parent path where you want to install.  If you want to install to
/home/cfautowr then navigate to /home

```bash
wget https://github.com/jwds1178/cfautowr/raw/master/cfautowr.sh;
```

Search-and-replace /home/cfautowr with the actual directory path where it's installed, your Cloudflare API token, Waiting Room ID, Zone ID

```bash
mkdir cfautowr;
cp cfautowr.sh cfautowr/cfautowr.sh
cd cfautowr;
chmod +x cfautowr.sh;
./cfautowr.sh -install;
```

It's now installed and running.  Check the logs and confirm it's working.


### Command Line Arguments
```
-install        : installs and enables service
-uninstall      : uninstalls and then deletes the sub folder
-disable_script : temporarily disables the service from running
-enable_script  : re-enables the service
-enable_wr     : enables Under Attack Mode manually
-disable_wr    : disables Under Attack Mode manually
```

### Notes
This script was designed to run out of it's own separate folder, if you change that you may have problems.
