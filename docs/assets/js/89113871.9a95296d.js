"use strict";(self.webpackChunknewdocs_openc_3_com=self.webpackChunknewdocs_openc_3_com||[]).push([[8309],{3905:(e,t,n)=>{n.d(t,{Zo:()=>u,kt:()=>h});var r=n(7294);function o(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function a(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);t&&(r=r.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,r)}return n}function i(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?a(Object(n),!0).forEach((function(t){o(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):a(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function l(e,t){if(null==e)return{};var n,r,o=function(e,t){if(null==e)return{};var n,r,o={},a=Object.keys(e);for(r=0;r<a.length;r++)n=a[r],t.indexOf(n)>=0||(o[n]=e[n]);return o}(e,t);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);for(r=0;r<a.length;r++)n=a[r],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(o[n]=e[n])}return o}var c=r.createContext({}),s=function(e){var t=r.useContext(c),n=t;return e&&(n="function"==typeof e?e(t):i(i({},t),e)),n},u=function(e){var t=s(e.components);return r.createElement(c.Provider,{value:t},e.children)},p="mdxType",m={inlineCode:"code",wrapper:function(e){var t=e.children;return r.createElement(r.Fragment,{},t)}},d=r.forwardRef((function(e,t){var n=e.components,o=e.mdxType,a=e.originalType,c=e.parentName,u=l(e,["components","mdxType","originalType","parentName"]),p=s(n),d=o,h=p["".concat(c,".").concat(d)]||p[d]||m[d]||a;return n?r.createElement(h,i(i({ref:t},u),{},{components:n})):r.createElement(h,i({ref:t},u))}));function h(e,t){var n=arguments,o=t&&t.mdxType;if("string"==typeof e||o){var a=n.length,i=new Array(a);i[0]=d;var l={};for(var c in t)hasOwnProperty.call(t,c)&&(l[c]=t[c]);l.originalType=e,l[p]="string"==typeof e?e:o,i[1]=l;for(var s=2;s<a;s++)i[s]=n[s];return r.createElement.apply(null,i)}return r.createElement.apply(null,n)}d.displayName="MDXCreateElement"},6957:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>c,contentTitle:()=>i,default:()=>m,frontMatter:()=>a,metadata:()=>l,toc:()=>s});var r=n(7462),o=(n(7294),n(3905));const a={title:"Contributing"},i=void 0,l={unversionedId:"meta/contributing",id:"meta/contributing",title:"Contributing",description:"So you've got an awesome idea to throw into COSMOS. Great! This is the basic process:",source:"@site/docs/meta/contributing.md",sourceDirName:"meta",slug:"/meta/contributing",permalink:"/docs/meta/contributing",draft:!1,editUrl:"https://github.com/OpenC3/cosmos/tree/main/docs.openc3.com/docs/meta/contributing.md",tags:[],version:"current",frontMatter:{title:"Contributing"},sidebar:"defaultSidebar",previous:{title:"Meta",permalink:"/docs/meta"},next:{title:"Philosophy",permalink:"/docs/meta/philosophy"}},c={},s=[{value:"Test Dependencies",id:"test-dependencies",level:2},{value:"Workflow",id:"workflow",level:2}],u={toc:s},p="wrapper";function m(e){let{components:t,...n}=e;return(0,o.kt)(p,(0,r.Z)({},u,n,{components:t,mdxType:"MDXLayout"}),(0,o.kt)("p",null,"So you've got an awesome idea to throw into COSMOS. Great! This is the basic process:"),(0,o.kt)("ol",null,(0,o.kt)("li",{parentName:"ol"},"Fork the project on Github"),(0,o.kt)("li",{parentName:"ol"},"Create a feature branch"),(0,o.kt)("li",{parentName:"ol"},"Make your changes"),(0,o.kt)("li",{parentName:"ol"},"Submit a pull request")),(0,o.kt)("admonition",{title:"Don't Forget the Contributor License Agreement!",type:"note"},(0,o.kt)("p",{parentName:"admonition"},"By contributing to this project, you accept our Contributor License Agreement which is found here: ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/OpenC3/cosmos/blob/main/CONTRIBUTING.txt"},"Contributor License Agreement")),(0,o.kt)("p",{parentName:"admonition"},"This protects both you and us and you retain full rights to any code you write.")),(0,o.kt)("h2",{id:"test-dependencies"},"Test Dependencies"),(0,o.kt)("p",null,"To run the test suite and build the gem you'll need to install COSMOS's\ndependencies. COSMOS uses Bundler, so a quick run of the ",(0,o.kt)("inlineCode",{parentName:"p"},"bundle")," command and\nyou're all set!"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-bash"},"\\$ bundle\n")),(0,o.kt)("p",null,"Before you start, run the tests and make sure that they pass (to confirm your\nenvironment is configured properly):"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-bash"},"\\$ bundle exec rake build spec\n")),(0,o.kt)("h2",{id:"workflow"},"Workflow"),(0,o.kt)("p",null,"Here's the most direct way to get your work merged into the project:"),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},"Fork the project."),(0,o.kt)("li",{parentName:"ul"},"Clone down your fork:")),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-bash"},"git clone git://github.com/<username>/openc3.git\n")),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},"Create a topic branch to contain your change:")),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-bash"},"git checkout -b my_awesome_feature\n")),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},"Hack away, add tests. Not necessarily in that order."),(0,o.kt)("li",{parentName:"ul"},"Make sure everything still passes by running ",(0,o.kt)("inlineCode",{parentName:"li"},"bundle exec rake"),"."),(0,o.kt)("li",{parentName:"ul"},"If necessary, rebase your commits into logical chunks, without errors."),(0,o.kt)("li",{parentName:"ul"},"Push the branch up:")),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-bash"},"git push origin my_awesome_feature\n")),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},"Create a pull request against openc3/cosmos:main and describe what your\nchange does and the why you think it should be merged.")),(0,o.kt)("admonition",{title:"Find a problem in the code or documentation?",type:"note"},(0,o.kt)("pre",{parentName:"admonition"},(0,o.kt)("code",{parentName:"pre"},"Please [create an issue](https://github.com/OpenC3/cosmos/issues/new/choose) on\nGitHub describing what we can do to make it better.\n"))))}m.isMDXComponent=!0}}]);