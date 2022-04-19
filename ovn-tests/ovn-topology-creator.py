#!/usr/bin/python3

import argparse
import os
import subprocess
import sys
import yaml

LOGICAL_ROUTER_TYPE = "LOGICAL_ROUTER"
LOGICAL_SWITCH_TYPE = "LOGICAL_SWITCH"
LOAD_BALANCER_TYPE = "LOAD_BALANCER"

OVN_ENTITIES_DEP = {
    LOAD_BALANCER_TYPE: 0,
    LOGICAL_SWITCH_TYPE: 10,
    LOGICAL_ROUTER_TYPE: 100
}


class OVNTopologyReader:
    def __init__(self, name, entities):
        self.name = name
        self._entities = {entity_type: [] for entity_type in OVN_ENTITIES_DEP}
        for e in entities:
            self._entities[e.get_type()].append(e)

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
        for ovn_entity in self.sorted_entities():
            if ovn_entity.add_to_ovn():
                return 1

        return 0

    def remove_from_ovn(self):
        for ovn_entity in self.sorted_entities(reverse=True):
            if ovn_entity.remove_from_ovn():
                return 1

        return 0

    @staticmethod
    def _read_topology_file(file_path):
        with open(file_path) as yaml_data:
            return yaml.safe_load(yaml_data)

    @staticmethod
    def _parse_topology_entity(entity_data):
        entity_type = entity_data.get("type")

        if entity_type == "switch":
            return OVNLogicalSwitch(entity_data)
        elif entity_type == "router":
            return OVNLogicalRouter(entity_data)
        elif entity_type == "loadBalancer":
            return OVNLoadBalancer(entity_data)

        raise RuntimeError(f'Unknown entity of type {entity_type}')

    def sorted_entities(self, reverse=False):
        """ return a sorted list of the topology entities according to dependencies """

        entities = []
        for el in self._entities.values():
            entities.extend(el)

        return sorted(entities, reverse=reverse, key=lambda e: OVN_ENTITIES_DEP[e.get_type()])


class OVNEntity:
    def __init__(self, data):
        self.name = data["name"]
        self._data = data

    def add_to_ovn(self):
        """Add ovn entity to OVN"""
        pass

    def remove_from_ovn(self):
        """Remove ovn entity to OVN"""
        pass

    def get_type(self):
        """Returns entity type"""
        pass


class OVNLogicalSwitch(OVNEntity):
    def __init__(self, data):
        super().__init__(data)
        self._ports = data["ports"]

    def __add_router_port(self, port, cmd_args):
        port_name = port["name"]
        router_port = port["routerPort"]
        cmd_args.append(f"lsp-set-type {port_name} router")
        cmd_args.append(f"lsp-set-addresses {port_name} router")
        cmd_args.append(f"lsp-set-options {port_name} router-port={router_port}")

    def __add_localnet_port(self, port, cmd_args):
        port_name = port["name"]
        cmd_args.append(f"lsp-set-type {port_name} localnet")
        cmd_args.append(f"lsp-set-addresses {port_name} unknown")

    def __add_port(self, port, cmd_args):
        port_name = port["name"]
        mac = port.get("mac")
        ips_v4 = port.get("ipv4")
        ips_v6 = port.get("ipv6")

        # Fail if IP provided with no mac
        if not mac and (ips_v4 or ips_v6):
            raise ValueError(f'Invalid: "{self.name}" switch has port "{port_name}" IP provided with no mac')

        addresses = mac
        if ips_v4:
            addresses += f" {' '.join(ips_v4)}"
        if ips_v6:
            addresses += f" {' '.join(ips_v6)}"
        cmd_args.append(f"lsp-set-addresses {port_name} \"{addresses}\"")

    def __add_port_type(self, port, cmd_args):
        port_type = port.get("type")
        if port_type == "router":
            self.__add_router_port(port, cmd_args)
        elif port_type == "localnet":
            self.__add_localnet_port(port, cmd_args)
        elif not port_type:
            self.__add_port(port, cmd_args)
        else:
            raise ValueError(f"Invalid: {self.name} switch has port {port['name']} with unknown type {port_type}")

    def __set_port_options(self, port, cmd_args):
        port_options = port.get("options")
        if port_options:
            cmd_args.append(f"lsp-set-options {port['name']} {' '.join(port_options)}")

    def __add_load_balancers(self, cmd_args):
        lbs = self._data.get("loadBalancers", [])
        for lb in lbs:
            cmd_args.append(f"--may-exist ls-lb-add {self.name} {lb}")

    def add_to_ovn(self):
        cmd_args = [f"--may-exist ls-add {self.name}"]
        self.__add_load_balancers(cmd_args)
        for port in self._ports:
            cmd_args.append(f"--may-exist lsp-add {self.name} {port['name']}")
            tag = port.get("tag")
            if tag:
                cmd_args.append(f"set LOGICAL_SWITCH_PORT {port['name']} tag={tag}")

            self.__set_port_options(port, cmd_args)
            self.__add_port_type(port, cmd_args)

        return run_ovn_nbctl(cmd_args)

    def remove_from_ovn(self):
        cmd_args = []
        for port in self._ports:
            cmd_args.append(f"--if-exists lsp-del {port['name']}")

        cmd_args.append(f"--if-exists ls-del {self.name}")
        return run_ovn_nbctl(cmd_args)

    def get_type(self):
        return LOGICAL_SWITCH_TYPE


class OVNLogicalRouter(OVNEntity):
    def __init__(self, data):
        super().__init__(data)
        self._ports = data["ports"]

    def get_ovs_id(self):
        with open('/etc/openvswitch/system-id.conf') as ovs_system_id_file:
            return ovs_system_id_file.read().strip()

    def __bind_to_chassis(self, cmd_args):
        """Bind OVN Gateway Router to chassis"""
        chassis = self._data.get("chassis")

        if not chassis:
            return

        if chassis.lower() == "local":
            chassis = self.get_ovs_id()

        cmd_args.append(f"set Logical_Router {self.name} options:chassis={chassis}")

    def __add_routes(self, cmd_args):
        routes = self._data.get("routes", [])
        for route in routes:
            cmd_args.append(f"lr-route-add {self.name} {route}")

    def __add_ports(self, cmd_args):
        for port in self._ports:
            port_name = port["name"]
            mac = port["mac"]
            ips_v4 = port.get("ipv4")
            ips_v6 = port.get("ipv6")
            chassis = port.get("chassis", [])

            # Fail if no IP/Network provided
            if not ips_v4 and not ips_v6:
                raise ValueError(f'Invalid: "{self.name}" router has port "{port_name}" with no IP/Network provided')

            addresses = mac
            if ips_v4:
                addresses += f" {' '.join(ips_v4)}"
            if ips_v6:
                addresses += f" {' '.join(ips_v6)}"

            cmd_args.append(f"--may-exist lrp-add {self.name} {port_name} {addresses}")
            for c in chassis:
                chassis_id = os.getenv(c, "")
                if chassis_id == "" and c == "local":
                    chassis_id = self.get_ovs_id()

                cmd_args.append(f"lrp-set-gateway-chassis {port_name} {chassis_id} 10")

    def __add_nats(self, cmd_args):
        nats = self._data.get("nats", [])
        for nat in nats:
            nat_type = nat["type"]
            external_ip = nat["external_ip"]
            logical_ip = nat["logical_ip"]
            port = nat.get("port", "")
            mac = nat.get("mac", "")

            if nat_type not in ("snat", "dnat", "dnat_and_snat"):
                raise ValueError(f'Invalid: "{self.name}" router has NAT with invalid type "{nat_type}"')

            cmd_args.append(f"lr-nat-add {self.name} {nat_type} {external_ip} {logical_ip} {port} {mac}")

    def __add_load_balancers(self, cmd_args):
        lbs = self._data.get("loadBalancers", [])
        for lb in lbs:
            cmd_args.append(f"--may-exist lr-lb-add {self.name} {lb}")

    def add_to_ovn(self):
        cmd_args = [f"--may-exist lr-add {self.name}"]

        self.__bind_to_chassis(cmd_args)
        self.__add_routes(cmd_args)
        self.__add_ports(cmd_args)
        self.__add_nats(cmd_args)
        self.__add_load_balancers(cmd_args)

        return run_ovn_nbctl(cmd_args)

    def remove_from_ovn(self):
        cmd_args = []
        for port in self._ports:
            cmd_args.append(f"--if-exists lrp-del {port['name']}")

        cmd_args.append(f"--if-exists lr-del {self.name}")
        return run_ovn_nbctl(cmd_args)

    def get_type(self):
        return LOGICAL_ROUTER_TYPE


class OVNLoadBalancer(OVNEntity):
    def __init__(self, data):
        super().__init__(data)

    def __set_options(self, cmd_args):
        options = self._data.get("options", [])
        for opt in options:
            cmd_args.append(f"set LOAD_BALANCER {self.name} options:{opt}")

    def add_to_ovn(self):
        ips = ",".join(self._data['ips'])
        protocol = self._data.get('protocol', '')
        if protocol not in ['', 'tcp', 'udp']:
            raise RuntimeError(f"Invalid loadBalancer \"{self.name}\" protocol \"{protocol}\"")

        cmd_args = [f"--may-exist lb-add {self.name} {self._data['vip']} {ips} {protocol}"]
        self.__set_options(cmd_args)
        return run_ovn_nbctl(cmd_args)

    def remove_from_ovn(self):
        return run_ovn_nbctl([f"--if-exists lb-del {self.name}"])

    def get_type(self):
        return LOAD_BALANCER_TYPE


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

        ret_code = 0
        if args.create:
            ret_code = topology.add_to_ovn()
        elif args.destroy:
            ret_code = topology.remove_from_ovn()
        else:
            return 1
    except Exception as ex:
        print(ex)
        return 1

    return ret_code


if __name__ == '__main__':
    rc = main()
    sys.exit(rc)
