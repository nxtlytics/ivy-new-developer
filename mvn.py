#!/usr/bin/env python3
import os
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom
from pathlib import Path
home = str(Path.home())
maven_settings = os.getenv('MVN_SETTINGS_XML', home +'/.m2/settings.xml')
output_file = os.getenv('MVN_SETTINGS_XML_OUTPUT', maven_settings)
ns_registration = ET.register_namespace('', 'http://maven.apache.org/SETTINGS/1.0.0')
tree = ET.parse(maven_settings)
root = tree.getroot()
nexus_server = os.getenv('MVN_SERVER_ID')
nexus_user = os.getenv('NEXUS_USER')
nexus_pass = os.getenv('NEXUS_PASS')

def indent(elem, level=0):
  i = "\n" + level*"  "
  if len(elem):
    if not elem.text or not elem.text.strip():
      elem.text = i + "  "
    if not elem.tail or not elem.tail.strip():
      elem.tail = i
    for elem in elem:
      indent(elem, level+1)
    if not elem.tail or not elem.tail.strip():
      elem.tail = i
  else:
    if level and (not elem.tail or not elem.tail.strip()):
      elem.tail = i

def append_to_servers(servers):
  print("I'm appending id, username and password")
  new_entry = ET.Element('server')
  new_server = ET.SubElement(new_entry, 'id').text = nexus_server
  username = ET.SubElement(new_entry, 'username').text = nexus_user
  password = ET.SubElement(new_entry, 'password').text = nexus_pass
  servers.append(new_entry)
  return servers

def write_xml_file(root, maven_settings):
  indent(root)
  tree.write(output_file, encoding='UTF-8', xml_declaration=True)

servers_tag = root.findall('{*}servers')

if len(servers_tag) == 0:
  print('there are no servers')
  root.append(ET.Element('servers'))
  servers_tag = root.findall('{*}servers')

servers = servers_tag[0].findall('{*}server')

if len(servers) == 0:
  print('there are no server entries, I will append it and exit')
  append_to_servers(servers_tag[0])
  write_xml_file(root, maven_settings)
  sys.exit(0)

servers_with_nexus = [ x for x in servers if x.find('{*}id').text == nexus_server ] or []

if len(servers_with_nexus) == 0:
  append_to_servers(servers_tag[0])
else:
  nexus = servers_with_nexus[0]
  username = nexus.find('{*}username')
  username.text = nexus_user
  password = nexus.find('{*}password')
  password.text = nexus_pass

write_xml_file(root, maven_settings)
