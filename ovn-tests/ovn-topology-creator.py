#!/usr/bin/python3

import argparse
import os
import subprocess
import sys
import yaml


class OVNTopologyReader:
    def __init__(self, name, entities):
        self.name = name
        self._entities = entities

    @classmethod
    def from_file(cls, file_path):
        if not os.path.isfile(file_path):
            raise FileNotFoundError(f'File "{file_path}" does not exist')

        data = cls._read_topology_file(file_path)
        name = data.get("name")
        ovn_entities = []

        for entity_data in data.get("topology", []):
            ovn_entities.append(cls._parse_topology_entity(entity_data))

        return cls(name, ovn_entities)

    def add_to_ovn(self):
        for ovn_entity in self._entities:
            if ovn_entity.add_to_ovn():
                return 1

        return 0

    def remove_from_ovn(self):
        for ovn_entity in self._entities:
            if ovn_entity.remove_from_ovn():
                return 1

        return 0

    @staticmethod
    def _read_topology_file(file_path):
        with open(file_path) as yaml_data:
            return yaml.safe_load(yaml_data)

    @staticmethod
    def _parse_topology_entity(entity_data):
        name = entity_data["name"]
        entity_type = entity_data.get("type", "")
        ports = entity_data.get("ports")

        if entity_type == "switch":
            return OVNLogicalSwitch(name, ports)

        raise RuntimeError(f'Unknown entity of type "{entity_type}"')


class OVNEntity:
    def __init__(self, name):
        self.name = name

    def add_to_ovn(self):
        """Add ovn entity to OVN"""
        pass

    def remove_from_ovn(self):
        """Remove ovn entity to OVN"""
        pass


class OVNLogicalSwitch(OVNEntity):
    def __init__(self, name, ports):
        super().__init__(name)

        self._ports = ports

    def add_to_ovn(self):
        cmd_args = [f"--may-exist ls-add {self.name}"]
        for port in self._ports:
            port_name = port["name"]
            cmd_args.append(f"--may-exist lsp-add {self.name} {port_name}")
            mac = port.get("mac")
            if mac:
                addresses = '"' + mac
                ips_v4 = port.get("ipv4", [])
                if ips_v4:
                    addresses += f" {' '.join(ips_v4)}"
                ips_v6 = port.get("ipv6", [])
                if ips_v6:
                    addresses += f" {' '.join(ips_v6)}"
                addresses += '"'
                cmd_args.append(f"lsp-set-addresses {port_name} {addresses}")

        return run_ovn_nbctl(cmd_args)

    def remove_from_ovn(self):
        cmd_args = []
        for port in self._ports:
            cmd_args.append(f"--if-exists lsp-del {port['name']}")

        cmd_args.append(f"--if-exists ls-del {self.name}")
        return run_ovn_nbctl(cmd_args)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--file', '-f', type=str, required=True,
                        help='OVN logical topology .yaml file')
    parser.add_argument('--create', '-c', action='store_true',
                        help='Create OVN logical topology')
    parser.add_argument('--destroy', '-d', action='store_true',
                        help='Destroy OVN logical topology')

    args = parser.parse_args()
    if (args.create and args.destroy) or (not args.create and not args.destroy):
        raise RuntimeError("Invalid args: Either use --create or --destroy")

    return args


def run_command(cmd, print_cmd=True, *args, **kwargs):
    if print_cmd:
        print(f"Running command: {cmd}")
    return subprocess.run(cmd, *args, capture_output=True, shell=True, **kwargs)


def run_ovn_nbctl(arguments):
    cmd = f"ovn-nbctl -- {' -- '.join(arguments)}"
    comp_ins = run_command(cmd)
    if comp_ins.returncode != 0:
        print(comp_ins.stderr)
        print(comp_ins.returncode)
        return 1

    return 0


def main():
    try:
        args = parse_args()
        topology = OVNTopologyReader.from_file(args.file)
        print(f"Topology: {topology.name}")
    except Exception as ex:
        print(ex)
        return 1

    ret_code = 0
    if args.create:
        ret_code = topology.add_to_ovn()
    elif args.destroy:
        ret_code = topology.remove_from_ovn()
    else:
        return 1

    return ret_code


if __name__ == '__main__':
    rc = main()
    sys.exit(rc)
