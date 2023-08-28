import proxmoxvm
import os
import sys
import json

proxmoxvm.addrunner("large", { "project": "jethub-homeassistant", "token": "1234567890" })

# Read args from env vars
GARM_COMMAND = os.getenv('GARM_COMMAND')
GARM_CONTROLLER_ID = os.getenv('GARM_CONTROLLER_ID')
GARM_PROVIDER_CONFIG_FILE = os.getenv('GARM_PROVIDER_CONFIG_FILE')
GARM_POOL_ID = os.getenv('GARM_POOL_ID')
GARM_INSTANCE_ID = os.getenv('GARM_INSTANCE_ID')

if GARM_COMMAND == "CreateInstance":
    # Run the create instance code
    # return:
    # In case of error, garm expects at the very least to see a non-zero exit code. If possible,
    # your executable should return as much information as possible via the above json, with the status field set to
    # error and the provider_fault set to a meaningful error message describing what has happened

    {
        "provider_id": "88818ff3-1fca-4cb5-9b37-84bfc3511ea6",
        "name": "garm-ny9HeeQYw2rl",
        "os_type": "linux",
        "os_name": "ubuntu",
        "os_version": "20.04",
        "os_arch": "x86_64",
        "status": "running",
        "pool_id": "41c4a43a-acee-493a-965b-cf340b2c775d",
        "provider_fault": ""
    }
    pass
elif GARM_COMMAND == "DeleteInstance":
    # Run the delete instance code
    pass
elif GARM_COMMAND == "ListInstances":
    # Run the list instances code
    pass
elif GARM_COMMAND == "GetInstance":
    # Run the get instance code
    pass
elif GARM_COMMAND == "RemoveAllInstances":
    # Run the remove all instances code
    pass
elif GARM_COMMAND == "Stop":
    # Run the stop code
    pass
elif GARM_COMMAND == "Start":
    # Run the start code
    pass
else:
    # handle unknown command
    print("unknown command %s" % GARM_COMMAND)
    exit(1)



data = json.load(sys.stdin)
for station in data["data"]:
    print(json.dumps(station))

