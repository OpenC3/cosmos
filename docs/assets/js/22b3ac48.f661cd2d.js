"use strict";(self.webpackChunkdocs_openc3_com=self.webpackChunkdocs_openc3_com||[]).push([["9146"],{317:function(e,n,r){r.r(n),r.d(n,{default:()=>p,frontMatter:()=>t,metadata:()=>s,assets:()=>a,toc:()=>c,contentTitle:()=>l});var s=JSON.parse('{"id":"guides/raspberrypi","title":"Raspberry Pi","description":"Running COSMOS on a Raspberry Pi","source":"@site/docs/guides/raspberrypi.md","sourceDirName":"guides","slug":"/guides/raspberrypi","permalink":"/docs/guides/raspberrypi","draft":false,"unlisted":false,"editUrl":"https://github.com/OpenC3/cosmos/tree/main/docs.openc3.com/docs/guides/raspberrypi.md","tags":[],"version":"current","frontMatter":{"title":"Raspberry Pi","description":"Running COSMOS on a Raspberry Pi","sidebar_custom_props":{"myEmoji":"\uD83C\uDF53"}},"sidebar":"defaultSidebar","previous":{"title":"Performance","permalink":"/docs/guides/performance"},"next":{"title":"Script Writing Guide","permalink":"/docs/guides/script-writing"}}'),i=r("5893"),o=r("65");let t={title:"Raspberry Pi",description:"Running COSMOS on a Raspberry Pi",sidebar_custom_props:{myEmoji:"\uD83C\uDF53"}},l=void 0,a={},c=[{value:"COSMOS Running on Raspberry Pi 4",id:"cosmos-running-on-raspberry-pi-4",level:3}];function d(e){let n={a:"a",code:"code",h3:"h3",li:"li",ol:"ol",p:"p",pre:"pre",ul:"ul",...(0,o.a)(),...e.components};return(0,i.jsxs)(i.Fragment,{children:[(0,i.jsx)(n.h3,{id:"cosmos-running-on-raspberry-pi-4",children:"COSMOS Running on Raspberry Pi 4"}),"\n",(0,i.jsx)(n.p,{children:"The Raspberry Pi 4 is a low-cost powerful ARM-based minicomputer that runs linux. And because it runs modern linux, it can also run COSMOS! These directions will get you up and running."}),"\n",(0,i.jsx)(n.p,{children:"What you'll need:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsx)(n.li,{children:"Raspberry Pi 4 board (tested with 8GB RAM)"}),"\n",(0,i.jsx)(n.li,{children:"A Pi Case but Optional"}),"\n",(0,i.jsx)(n.li,{children:"Raspbeerry Pi Power Supply"}),"\n",(0,i.jsx)(n.li,{children:"32GB or Larger SD Card - Also faster the better"}),"\n",(0,i.jsx)(n.li,{children:"A Laptop with a way to write SD Cards"}),"\n"]}),"\n",(0,i.jsx)(n.p,{children:"Let's get started!"}),"\n",(0,i.jsxs)(n.ol,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Setup 64-bit Raspian OS Lite on the SD Card"}),"\n",(0,i.jsxs)(n.p,{children:["Make sure you have the Raspberry Pi Imager app from: ",(0,i.jsx)(n.a,{href:"https://www.raspberrypi.com/software/",children:"https://www.raspberrypi.com/software/"})]}),"\n",(0,i.jsxs)(n.ol,{children:["\n",(0,i.jsx)(n.li,{children:"Insert the SD Card into your computer (Note this process will erase all data on the SD card!)"}),"\n",(0,i.jsx)(n.li,{children:"Open the Raspberry Pi Imager App"}),"\n",(0,i.jsx)(n.li,{children:'Click the "Choose Device" Button'}),"\n",(0,i.jsx)(n.li,{children:"Pick Your Raspberry Pi Model"}),"\n",(0,i.jsx)(n.li,{children:'Click the "Choose OS" Button'}),"\n",(0,i.jsx)(n.li,{children:'Select "Raspberry Pi OS (other)"'}),"\n",(0,i.jsx)(n.li,{children:'Select "Raspberry Pi OS Lite (64-bit)"'}),"\n",(0,i.jsx)(n.li,{children:'Click the "Choose Storage" Button'}),"\n",(0,i.jsx)(n.li,{children:"Select Your SD Card"}),"\n",(0,i.jsx)(n.li,{children:"Click Edit Settings"}),"\n",(0,i.jsx)(n.li,{children:"If prompted if you would like to prefill the Wifi information, select OK"}),"\n",(0,i.jsx)(n.li,{children:"Set the hostname to: cosmos.local"}),"\n",(0,i.jsx)(n.li,{children:"Set the username and password. The default username is your username, you should also set a password to make the system secure"}),"\n",(0,i.jsx)(n.li,{children:"Fill in your Wifi info, and set the country appropriately (ie. US)"}),"\n",(0,i.jsx)(n.li,{children:"Set the correct time zone"}),"\n",(0,i.jsx)(n.li,{children:"Goto the Services Tab and Enable SSH"}),"\n",(0,i.jsx)(n.li,{children:"You can either use Password auth, or public-key only if your computer is already setup for passwordless SSH"}),"\n",(0,i.jsx)(n.li,{children:'Goto the Options tab and make sure "Enable Telemetry" is not checked'}),"\n",(0,i.jsx)(n.li,{children:'Click "Save" when everything is filled out'}),"\n",(0,i.jsx)(n.li,{children:'Click "Yes" to apply OS Customization Settings, Yes to Are You Sure, and Wait for it to complete'}),"\n"]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Make sure the Raspberry Pi is NOT powered on"}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Remove the SD Card from your computer and insert into the Raspberry Pi"}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Apply power to the Raspberry Pi and wait approximately 1 minute for it to boot"}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"SSH to your raspberry Pi"}),"\n",(0,i.jsxs)(n.ol,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Open a terminal window and use ssh to connect to your Pi"}),"\n",(0,i.jsxs)(n.ol,{children:["\n",(0,i.jsxs)(n.li,{children:["On Mac / Linux: ssh ",(0,i.jsx)(n.a,{href:"mailto:yourusername@cosmos.local",children:"yourusername@cosmos.local"})]}),"\n",(0,i.jsx)(n.li,{children:"On Windows, use Putty to connect. You will probably have to install Bonjour for Windows for .local addresses to work as well."}),"\n"]}),"\n"]}),"\n"]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"From SSH, Enter the following commands"}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"   sudo sysctl -w vm.max_map_count=262144\n   sudo sysctl -w vm.overcommit_memory=1\n   sudo apt update\n   sudo apt upgrade\n   sudo apt install git -y\n   curl -fsSL https://get.docker.com -o get-docker.sh\n   sudo sh get-docker.sh\n   sudo usermod -aG docker $USER\n   newgrp docker\n   git clone https://github.com/OpenC3/cosmos-project.git cosmos\n   cd cosmos\n   # Edit compose.yaml and remove 127.0.0.1: from the ports section of the openc3-traefik service\n   ./openc3.sh run\n"})}),"\n",(0,i.jsxs)(n.ol,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["After about 2 minutes, open a web browser on your computer, and goto: ",(0,i.jsx)(n.a,{href:"http://cosmos.local:2900",children:"http://cosmos.local:2900"})]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Congratulations! You now have COSMOS running on a Raspberry Pi!"}),"\n"]}),"\n"]})]})}function p(e={}){let{wrapper:n}={...(0,o.a)(),...e.components};return n?(0,i.jsx)(n,{...e,children:(0,i.jsx)(d,{...e})}):d(e)}},65:function(e,n,r){r.d(n,{Z:function(){return l},a:function(){return t}});var s=r(7294);let i={},o=s.createContext(i);function t(e){let n=s.useContext(o);return s.useMemo(function(){return"function"==typeof e?e(n):{...n,...e}},[n,e])}function l(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:t(e.components),s.createElement(o.Provider,{value:n},e.children)}}}]);