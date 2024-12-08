"use strict";(self.webpackChunkdocs_openc3_com=self.webpackChunkdocs_openc3_com||[]).push([["314"],{772:function(e,n,i){i.r(n),i.d(n,{metadata:()=>t,contentTitle:()=>a,default:()=>u,assets:()=>d,toc:()=>l,frontMatter:()=>o});var t=JSON.parse('{"id":"guides/bridges","title":"Bridges","description":"Bridge data into COSMOS from serial ports, PCI, etc","source":"@site/docs/guides/bridges.md","sourceDirName":"guides","slug":"/guides/bridges","permalink":"/docs/guides/bridges","draft":false,"unlisted":false,"editUrl":"https://github.com/OpenC3/cosmos/tree/main/docs.openc3.com/docs/guides/bridges.md","tags":[],"version":"current","frontMatter":{"title":"Bridges","description":"Bridge data into COSMOS from serial ports, PCI, etc","sidebar_custom_props":{"myEmoji":"\uD83C\uDF09"}},"sidebar":"defaultSidebar","previous":{"title":"Guides","permalink":"/docs/guides"},"next":{"title":"COSMOS and NASA cFS","permalink":"/docs/guides/cfs"}}'),r=i("5893"),s=i("65");let o={title:"Bridges",description:"Bridge data into COSMOS from serial ports, PCI, etc",sidebar_custom_props:{myEmoji:"\uD83C\uDF09"}},a=void 0,d={},l=[{value:"Bridges are Generally Just an Interface and Router",id:"bridges-are-generally-just-an-interface-and-router",level:2},{value:"Host Requirements for Running Bridges",id:"host-requirements-for-running-bridges",level:2},{value:"Bridge Configuration: bridge.txt",id:"bridge-configuration-bridgetxt",level:2},{value:"Bridge Commands: openc3cli",id:"bridge-commands-openc3cli",level:2},{value:"Example Bridge Gems",id:"example-bridge-gems",level:2},{value:"Note on Serial Ports",id:"note-on-serial-ports",level:2}];function c(e){let n={a:"a",admonition:"admonition",code:"code",h2:"h2",li:"li",p:"p",pre:"pre",ul:"ul",...(0,s.a)(),...e.components};return(0,r.jsxs)(r.Fragment,{children:[(0,r.jsx)(n.p,{children:"COSMOS Bridges provide an easy solution for getting data from devices that don't speak Ethernet into COSMOS.\nSerial ports are the most common, but other devices such as USB, PCI cards, and Bluetooth devices can also be\nsupported by using bridges to convert from a host computer accessible device, into an Ethernet byte stream that COSMOS can process from inside of containers."}),"\n",(0,r.jsx)(n.admonition,{title:"Bridges are Meant to be Dumb",type:"warning",children:(0,r.jsx)(n.p,{children:"The purpose of bridges is to get bytes into COSMOS. Processing should be done in COSMOS itself, including details such as\npacket delineation."})}),"\n",(0,r.jsx)(n.h2,{id:"bridges-are-generally-just-an-interface-and-router",children:"Bridges are Generally Just an Interface and Router"}),"\n",(0,r.jsx)(n.p,{children:"Bridges are generally made up of a COSMOS Interface class that pull data from a host connected device, and a Router that forwards that data to\nCOSMOS over TCP/IP. In most cases, data can be safely sent to COSMOS using the BURST protocol, and let the COSMOS side use the correct packet delineation\nprotocol like LENGTH."}),"\n",(0,r.jsx)(n.h2,{id:"host-requirements-for-running-bridges",children:"Host Requirements for Running Bridges"}),"\n",(0,r.jsxs)(n.ul,{children:["\n",(0,r.jsx)(n.li,{children:"Requires a host Ruby installation (Ruby 3)"}),"\n",(0,r.jsxs)(n.li,{children:["Install the OpenC3 gem","\n",(0,r.jsxs)(n.ul,{children:["\n",(0,r.jsx)(n.li,{children:"gem install openc3"}),"\n"]}),"\n"]}),"\n",(0,r.jsxs)(n.li,{children:["Make sure the Ruby gem executable path is in your PATH environment variable","\n",(0,r.jsxs)(n.ul,{children:["\n",(0,r.jsxs)(n.li,{children:["You can find this path by running ",(0,r.jsx)(n.code,{children:"gem environment"})," and looking for EXECUTABLE DIRECTORY"]}),"\n"]}),"\n"]}),"\n",(0,r.jsxs)(n.li,{children:["If successful, you should be able to run ",(0,r.jsx)(n.code,{children:"openc3cli"})," from a terminal"]}),"\n"]}),"\n",(0,r.jsx)(n.h2,{id:"bridge-configuration-bridgetxt",children:"Bridge Configuration: bridge.txt"}),"\n",(0,r.jsx)(n.p,{children:"Bridges are run using an configuration file named bridge.txt. This file is a subset of the plugin.txt configuration syntax supporting VARIABLE, INTERFACE, ROUTER, and associated modifier keywords. However, BRIDGES HAVE NO KNOWLEDGE OF TARGETS. So instead of MAP_TARGETS, the INTERFACE is associated with the ROUTER using the ROUTE keyword."}),"\n",(0,r.jsxs)(n.p,{children:["The following is the default bridge.txt that is generated by running ",(0,r.jsx)(n.code,{children:"openc3cli bridgesetup"})]}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{className:"language-ruby",children:"# Write serial port name\nVARIABLE write_port_name COM1\n\n# Read serial port name\nVARIABLE read_port_name COM1\n\n# Baud Rate\nVARIABLE baud_rate 115200\n\n# Parity - NONE, ODD, or EVEN\nVARIABLE parity NONE\n\n# Stop bits - 0, 1, or 2\nVARIABLE stop_bits 1\n\n# Write Timeout\nVARIABLE write_timeout 10.0\n\n# Read Timeout\nVARIABLE read_timeout nil\n\n# Flow Control - NONE, or RTSCTS\nVARIABLE flow_control NONE\n\n# Data bits per word - Typically 8\nVARIABLE data_bits 8\n\n# Port to listen for connections from COSMOS - Plugin must match\nVARIABLE router_port 2950\n\n# Port to listen on for connections from COSMOS. Defaults to localhost for security. Will need to be opened\n# if COSMOS is on another machine.\nVARIABLE router_listen_address 127.0.0.1\n\nINTERFACE SERIAL_INT serial_interface.rb <%= write_port_name %> <%= read_port_name %> <%= baud_rate %> <%= parity %> <%= stop_bits %> <%= write_timeout %> <%= read_timeout %>\n  OPTION FLOW_CONTROL <%= flow_control %>\n  OPTION DATA_BITS <%= data_bits %>\n\nROUTER SERIAL_ROUTER tcpip_server_interface.rb <%= router_port %> <%= router_port %> 10.0 nil BURST\n  ROUTE SERIAL_INT\n  OPTION LISTEN_ADDRESS <%= router_listen_address %>\n"})}),"\n",(0,r.jsx)(n.p,{children:"VARIABLE provides default values to variables that can be changed when the bridge is started. This example shows an INTERFACE that is configured to use the serial_interface.rb class. It also includes a standard ROUTER using tcpip_server_interface.rb that COSMOS can connect to and get the data from the serial port. The LISTEN_ADDRESS is set to 127.0.0.1 in this example to prevent access from outside of the host system. Docker running on the same machine can access\nthis server using the host.docker.internal hostname and the configured port (2950 in this example)."}),"\n",(0,r.jsx)(n.h2,{id:"bridge-commands-openc3cli",children:"Bridge Commands: openc3cli"}),"\n",(0,r.jsx)(n.p,{children:(0,r.jsx)(n.code,{children:"openc3cli bridgesetup"})}),"\n",(0,r.jsx)(n.p,{children:"Generates a bridge.txt example file"}),"\n",(0,r.jsx)(n.p,{children:(0,r.jsx)(n.code,{children:"openc3cli bridge [filename] [variable1=value1] [variable2=value2]"})}),"\n",(0,r.jsx)(n.p,{children:"Runs a bridge from a given configuration file. Defaults to bridge.txt in the current directory. Variables can also be passed into to override VARIABLE defaults."}),"\n",(0,r.jsx)(n.p,{children:(0,r.jsx)(n.code,{children:"openc3cli bridgegem [gem_name] [variable1=value1] [variable2=value2]"})}),"\n",(0,r.jsx)(n.p,{children:"Runs a bridge using the bridge.txt provided in a bridge gem. Variables can also be passed into to override VARIABLE defaults."}),"\n",(0,r.jsx)(n.h2,{id:"example-bridge-gems",children:"Example Bridge Gems"}),"\n",(0,r.jsxs)(n.ul,{children:["\n",(0,r.jsxs)(n.li,{children:["Serial Port: ",(0,r.jsx)(n.a,{href:"https://github.com/OpenC3/openc3-cosmos-bridge-serial",children:"openc3-cosmos-bridge-serial"})]}),"\n",(0,r.jsxs)(n.li,{children:["Host: ",(0,r.jsx)(n.a,{href:"https://github.com/OpenC3/openc3-cosmos-bridge-host",children:"openc3-cosmos-bridge-host"})]}),"\n",(0,r.jsxs)(n.li,{children:["HIDAPI: ",(0,r.jsx)(n.a,{href:"https://github.com/OpenC3/openc3-cosmos-bridge-hidapi",children:"openc3-cosmos-bridge-hidapi"})]}),"\n",(0,r.jsxs)(n.li,{children:["PS5 Dual Sense Controller: ",(0,r.jsx)(n.a,{href:"https://github.com/OpenC3/openc3-cosmos-bridge-dualsense",children:"openc3-cosmos-bridge-dualsense"})]}),"\n"]}),"\n",(0,r.jsx)(n.h2,{id:"note-on-serial-ports",children:"Note on Serial Ports"}),"\n",(0,r.jsx)(n.p,{children:"Serial ports can be used directly without bridges on Linux Docker installations."}),"\n",(0,r.jsx)(n.p,{children:"Add the following to the operator service in compose.yaml:"}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{children:'   devices:\n     - "/dev/ttyUSB0:/dev/ttyUSB0"\n'})}),"\n",(0,r.jsx)(n.p,{children:"Make sure the serial device has permissions for the user running Docker to access:"}),"\n",(0,r.jsx)(n.pre,{children:(0,r.jsx)(n.code,{children:"sudo chmod 666 /dev/ttyUSB0\n"})})]})}function u(e={}){let{wrapper:n}={...(0,s.a)(),...e.components};return n?(0,r.jsx)(n,{...e,children:(0,r.jsx)(c,{...e})}):c(e)}},65:function(e,n,i){i.d(n,{Z:function(){return a},a:function(){return o}});var t=i(7294);let r={},s=t.createContext(r);function o(e){let n=t.useContext(s);return t.useMemo(function(){return"function"==typeof e?e(n):{...n,...e}},[n,e])}function a(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(r):e.components||r:o(e.components),t.createElement(s.Provider,{value:n},e.children)}}}]);