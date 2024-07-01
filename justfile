justfile-checkout:
  cd {{ justfile_directory() }}; \
  git checkout justfile -- justfile

_sync USERHOST:
  dir=$(basename $(pwd)); \
  cd {{ justfile_directory() }}; \
  rsync -avz --delete --exclude .git -e ssh . {{ USERHOST }}:$dir

sync ENV:
  case {{ ENV }} in \
    lab) \
      userhost=ubuntu@63.131.145.238 ;; \
    sjc) \
      userhost="gu=adam5637@adam5637@66.70.54.105@support.dfw1.gateway.rackspace.com" ;; \
    sjc-ubuntu) \
      userhost="gu=adam5637@ubuntu@66.70.54.105@support.dfw1.gateway.rackspace.com" ;; \
    dfw) \
      userhost="gu=adam5637@adam5637@10.5.83.147@support.dfw1.gateway.rackspace.com" ;; \
    dfw-ubuntu) \
      userhost="gu=adam5637@ubuntu@10.5.83.147@support.dfw1.gateway.rackspace.com" ;; \
  esac ; \
  just _sync $userhost
