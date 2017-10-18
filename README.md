# OVS Tests

A collection of tests for the openvswitch offload project.
Each test has a prefix of "test-". Beside test-all.py which is used to run all tests.

Almost all tests require PF/VF/representor or some other configuration which is per host.
or per device. i.e. if we want to test ConnectX-4 or ConnectX-5. first port or second port. etc.
For this there is a config file that can be used across the tests. See for example "config_dev139.sh".

To use the config file export it as CONFIG.
E.g. export CONFIG=config_dev139.sh
