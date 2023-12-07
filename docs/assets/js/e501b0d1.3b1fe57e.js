"use strict";(self.webpackChunkdocs_openc3_com=self.webpackChunkdocs_openc3_com||[]).push([[1358],{2450:(e,t,i)=>{i.r(t),i.d(t,{assets:()=>d,contentTitle:()=>a,default:()=>h,frontMatter:()=>s,metadata:()=>c,toc:()=>l});var n=i(5893),o=i(1151);const s={title:"Local Mode"},a=void 0,c={id:"guides/local-mode",title:"Local Mode",description:"Local Mode is a new feature in the 5.0.9 COSMOS release. It is intended to capture the configuration of an edited plugin so it can be configuration managed. It allows you to edit portions of a plugin (scripts and screens) locally in the editor of your choice and instantly have those changes appear in the COSMOS plugin. This avoids the plugin build / install cycle which is required when editing command and telemetry or interface definitions.",source:"@site/docs/guides/local-mode.md",sourceDirName:"guides",slug:"/guides/local-mode",permalink:"/docs/guides/local-mode",draft:!1,unlisted:!1,editUrl:"https://github.com/OpenC3/cosmos/tree/main/docs.openc3.com/docs/guides/local-mode.md",tags:[],version:"current",frontMatter:{title:"Local Mode"},sidebar:"defaultSidebar",previous:{title:"Little Endian Bitfields",permalink:"/docs/guides/little-endian-bitfields"},next:{title:"Logging",permalink:"/docs/guides/logging"}},d={},l=[{value:"Using Local Mode",id:"using-local-mode",level:2},{value:"Editing scripts",id:"editing-scripts",level:3},{value:"Disabling Local Mode",id:"disabling-local-mode",level:3},{value:"Configuration Management",id:"configuration-management",level:2}];function r(e){const t={a:"a",admonition:"admonition",code:"code",em:"em",h2:"h2",h3:"h3",img:"img",p:"p",pre:"pre",...(0,o.a)(),...e.components};return(0,n.jsxs)(n.Fragment,{children:[(0,n.jsx)(t.p,{children:"Local Mode is a new feature in the 5.0.9 COSMOS release. It is intended to capture the configuration of an edited plugin so it can be configuration managed. It allows you to edit portions of a plugin (scripts and screens) locally in the editor of your choice and instantly have those changes appear in the COSMOS plugin. This avoids the plugin build / install cycle which is required when editing command and telemetry or interface definitions."}),"\n",(0,n.jsx)(t.h2,{id:"using-local-mode",children:"Using Local Mode"}),"\n",(0,n.jsxs)(t.p,{children:["In this tutorial we will use the COSMOS Demo as configured by the ",(0,n.jsx)(t.a,{href:"/docs/getting-started/installation",children:"Installation Guide"}),". You should have cloned a ",(0,n.jsx)(t.a,{href:"https://github.com/OpenC3/cosmos-project",children:"cosmos-project"})," and started it using ",(0,n.jsx)(t.code,{children:"openc3.sh run"}),"."]}),"\n",(0,n.jsxs)(t.p,{children:["If you check the project directory you should see a ",(0,n.jsx)(t.code,{children:"plugins/DEFAULT/openc3-cosmos-demo"})," directory. This will contain both the gem that was installed and a ",(0,n.jsx)(t.code,{children:"plugin_instance.json"})," file. The ",(0,n.jsx)(t.code,{children:"plugin_instance.json"})," file captures the plugin.txt values when the plugin was installed. Note, all files in the plugins directory are meant to be configuration managed with the project. This ensures if you make local edits and check them in, another user can clone the project and get the exact same configuration. We will demonstrate this later."]}),"\n",(0,n.jsx)(t.h3,{id:"editing-scripts",children:"Editing scripts"}),"\n",(0,n.jsx)(t.admonition,{title:"Visual Studio Code",type:"info",children:(0,n.jsxs)(t.p,{children:["This tutorial will use ",(0,n.jsx)(t.a,{href:"https://code.visualstudio.com",children:"VS Code"})," which is the editor used by the COSMOS developers."]})}),"\n",(0,n.jsxs)(t.p,{children:["The most common use case for Local Mode is script development. Launch Script Runner and open the ",(0,n.jsx)(t.code,{children:"INST/procedures/checks.rb"})," file. If you run this script you'll notice that it has a few errors (by design) which prevent it from running to completion. Let's fix it! Comment out the second and fourth lines and save the script. You should now notice that Local Mode has saved a copy of the script to ",(0,n.jsx)(t.code,{children:"plugins/targets_modified/INST/procedures/checks.rb"}),"."]}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(7891).Z+"",width:"926",height:"325"})}),"\n",(0,n.jsxs)(t.p,{children:["At this point Local Mode keeps these scripts in sync so we can edit in either place. Let's edit the local script by adding a simple comment at the top: ",(0,n.jsx)(t.code,{children:"# This is a script"}),". Now if we go back to Script Runner the changes have not ",(0,n.jsx)(t.em,{children:"automatically"})," appeared. However, there is a Reload button next to the filename that will refresh the file from the backend."]}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(738).Z+"",width:"845",height:"360"})}),"\n",(0,n.jsx)(t.p,{children:"Clicking this reloads the file which has been synced into COSMOS and now we see our comment."}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(5682).Z+"",width:"536",height:"102"})}),"\n",(0,n.jsxs)(t.p,{children:["It's important not to delete this local file while in Local Mode or COSMOS will display a server error 500. If this happens you can open the Minio Console at ",(0,n.jsx)(t.a,{href:"http://localhost:2900/minio/",children:"http://localhost:2900/minio/"})," and browse to the file in question to download and restore it."]}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(6196).Z+"",width:"1312",height:"442"})}),"\n",(0,n.jsx)(t.h3,{id:"disabling-local-mode",children:"Disabling Local Mode"}),"\n",(0,n.jsxs)(t.p,{children:["If you want to disable Local Mode you can edit the .env file and delete the setting ",(0,n.jsx)(t.code,{children:"OPENC3_LOCAL_MODE=1"}),"."]}),"\n",(0,n.jsx)(t.h2,{id:"configuration-management",children:"Configuration Management"}),"\n",(0,n.jsx)(t.p,{children:"It is recommended to configuration manage the entire project including the plugins directory. This will allow any user who starts COSMOS to launch an identical configuration. Plugins are created and updated with any modifications found in the targets_modified directory."}),"\n",(0,n.jsx)(t.p,{children:"At some point you will probably want to release your local changes back to the plugin they originated from. Simply copy the entire targets_modified/TARGET directory back to the original plugin. At that point you can rebuild the plugin using the CLI."}),"\n",(0,n.jsx)(t.pre,{children:(0,n.jsx)(t.code,{children:"openc3-cosmos-demo % ./openc3.sh cli rake build VERSION=1.0.1\n  Successfully built RubyGem\n  Name: openc3-cosmos-demo\n  Version: 1.0.1\n  File: openc3-cosmos-demo-1.0.1.gem\n"})}),"\n",(0,n.jsx)(t.p,{children:"Upgrade the plugin using the Admin Plugins tab and the Upgrade link. When you select your newly built plugin, COSMOS detects the existing changes and asks if you want to delete them. There is a stern warning attached because this will permanently remove these changes! Since we just moved over the changes and rebuilt the plugin we will check the box and INSTALL."}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(7574).Z+"",width:"1057",height:"583"})}),"\n",(0,n.jsxs)(t.p,{children:["When the new plugin is installed, the project's ",(0,n.jsx)(t.code,{children:"plugins"})," directory gets updated with the new plugin and everything under the targets_modified directory is removed because there are no modifications on a new install."]}),"\n",(0,n.jsx)(t.p,{children:(0,n.jsx)(t.img,{alt:"Project Layout",src:i(6118).Z+"",width:"353",height:"305"})}),"\n",(0,n.jsx)(t.p,{children:"Local Mode is a powerful way to develop scripts and screens on the local file system and automatically have them sync to COSMOS."})]})}function h(e={}){const{wrapper:t}={...(0,o.a)(),...e.components};return t?(0,n.jsx)(t,{...e,children:(0,n.jsx)(r,{...e})}):r(e)}},7574:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/delete_modified-a7ec0ceb61c37398d57fcecf11ebe2453ebd0110be6cfc960a5073a13a557638.png"},6196:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/minio-150460ac77a50711835de6f0150d019000e5515afae0f3adfcdda8e891484f47.png"},7891:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/project-fe7ac90f3e45971fca8f1be94be9dbabe494bafe705e7f8f485676e9d96e47ea.png"},6118:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/project_update-8e7de3b0658b95d4d9931eb52ff8bf339d633cbdc273ce096eb11ceb357c009e.png"},738:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/reload_file-8e26cd3e1bc1eab7bb6c046d9a6a8231fcd76e56682d819b1e549182890c6486.png"},5682:(e,t,i)=>{i.d(t,{Z:()=>n});const n=i.p+"assets/images/reloaded-9effa15527244928ee503eb0c3a48cc5e82c07cfb5d5c4300eacfcab913069d1.png"},1151:(e,t,i)=>{i.d(t,{Z:()=>c,a:()=>a});var n=i(7294);const o={},s=n.createContext(o);function a(e){const t=n.useContext(s);return n.useMemo((function(){return"function"==typeof e?e(t):{...t,...e}}),[t,e])}function c(e){let t;return t=e.disableParentContext?"function"==typeof e.components?e.components(o):e.components||o:a(e.components),n.createElement(s.Provider,{value:t},e.children)}}}]);