# OVS Tests

A collection of tests for the openvswitch TC offload project.  
Each test has a prefix of "test-". second word is for grouping related tests.
test-all.py is a wrapper to easily run all tests.                            

Before running tests need to create a config file. see examples that already
exists. then export it to var CONFIG.                                       
The config file needs to exists in current directory or with the tests.     

Example to run atest:

```
export CONFIG=config_dev139.sh
~/ovs-tests/test-tc-insert-rules.sh
```
