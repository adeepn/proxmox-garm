
pvesh get /cluster/nextid
pvesh get /cluster/resources --type vm --output-format json|jq '.[] | select (.status!="running")'


 250  qm
  254  qm template 9000
  275  touch qm.sh
  276  qm list
  277  ./qm.sh
  278  qm set 9000 --ide2 vm:cloudinit
  279  ./qm.sh
  281  qm set 100
  282  qm set 100 --help
  283  qm set 100 -h
  284  qm set 100 help
  285  qm set 100 e
  286  qm set 100 en
  287  qm set 100 env
  288  qm set 100 --cicustom "TOKEN=qwer,repo=fff/ggg"
  289  qm cloudinit dump 100 user
  290  qm cloudinit dump 100 
  291  qm cloudinit dump 100 server
  292  qm cloudinit dump 100 user
  293  qm 100 start
  294  qm start 100
  295  qm disk import 100 test/jammy-server-cloudimg-amd64.img vm
  314  ./qm.sh
  320  qm
  336  qm create 9000 --name "ubuntu-template" --memory 16384 --cores 8 --net0 virtio,bridge=vmbr1
  337  qm importdisk 9000 jammy-server-cloudimg-amd64.img 
  338  qm importdisk 9000 jammy-server-cloudimg-amd64.img runner3vm
  339  qm set 9000 --scsihw virtio-scsi-single --scsi0 local-zfs:vm-9000-disk-0
  340  qm set 9000 --scsihw virtio-scsi-single --scsi0 runner3vm:vm-9000-disk-0
  341  qm set 9000 --boot c --bootdisk scsi0
  342  qm set 9000 --ide2 local-zfs:cloudinit
  343  qm set 9000 --ide2 runner3vm:cloudinit
  344  qm set 9000 --serial0 socket --vga serial0
  345  qm set 9000 --agent enabled=1
  346  qm template 9000
  347  qm clone 9000 999 --name test-clone-cloud-init
  349  qm clone 9000 999 --name test-clone-cloud-init
  350  qm set 999 --sshkey ~/.ssh/id_rsa.pub
  351  qm set 999 --ipconfig0 ip=DHCP
  352  qm start 999
  379  qm
  380  qm pvesh get /cluster/resources --type vm
  390  qm list
  391  qm set 100 --hook-script=auto-delete.sh
  392  qm set 100 --hookscript local:snippets/auto-delete.sh
  395  qm set 100 --hookscript local:snippets/auto-delete.sh
  401  qm set 100 --hookscript local:snippets/auto-delete.sh
  434  qm set 100 
  435  qm set 100  hook
  436  history |grep qm
