ye  --  Yaml Editor
This application is a wrapper around vim. It is designed to pull the base helm config and the corosponding 
override file. Merge them together and allow you to edit them in one place. Then when you save, it will
update the overrides file with the new config. Leaving the base file unchanged.

Syntax: ye <project name>
Example: ye nova
