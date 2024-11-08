---
title: Licenses
description: COSMOS licenses including the AGPLv3 vs Commercial
sidebar_custom_props:
  myEmoji: 🕵️
---

OpenC3 COSMOS is offered under a tri-licensing model allowing users to choose between the following three options:

## AGPLv3

This is our default open source license and the license that most free users use. The AGPLv3 is a modification of the GPLv3 which is what is known as a copy-left license or a viral license. You can read the whole thing here: [OpenC3 AGPLv3](https://github.com/OpenC3/cosmos/blob/main/LICENSE.txt)

Obviously, the actual license text applies, but here is a short summary:

- The AGPL allows users to use the code however they want: For business, personal, etc., as long as they follow the other terms:

  1. Users are anyone who could access the web-app. On the public internet, that is the whole world. On a private network, it is anyone with access to that network.

  2. The software is provided as-is, no warranty

  3. Users must be given access to all the source code and are also allowed to use it however they want under the same terms of the AGPLv3. This includes any modifications made, anything added, and all plugins.

  4. For web applications (like COSMOS), a link must be provided to all of the source code.

- There are some key implications of the above:

  1. You cannot keep anything proprietary from your users. They have the rights to take the code (and configuration) and do anything they want with it. You CANNOT impede these rights or you are violating the AGPLv3 and YOU lose the rights to use our software.

  2. You must provide a digital link to all source code for your users, including plugins.

  3. All plugins must be licensed in an AGPLv3 compatible fashion. We recommend the MIT license because that allows your plugins to be compatible with the AGPLv3 and our commercial license. You can also use a dual license similar to what we do indicating the AGPLv3 or a purchased OpenC3 Commercial license.

The AGPLv3 license is often chosen because it works well for open core products like COSMOS. Competitors cannot take the open source product and license it under different terms. They would be forever locked into the AGPLv3 which is difficult to monetize, because your customers can take any code you provide and publish it on the internet for free use by everyone.

As the copyright holder, OpenC3 is able to license the product and derivatives commercially. No-one else can do this. (OpenC3 is also able to license legacy Ball Aerospace COSMOS code under IP agreement)

## Evaluation and Education Use Only

This license takes effect as soon as you use any plugin we publish under Evaluation and Education terms. Currently the only plugin we use for this is our CCSDS CFDP plugin: [CFDP Plugin](https://github.com/OpenC3/openc3-cosmos-cfdp)

You can read the whole license here:

```
# OpenC3 Evaluation and Educational License
#
# Copyright 2023 OpenC3, Inc.
#
# This work is licensed for evaluation and educational purposes only.
# It may NOT be used for formal development, integration and test, operations
# or any other commercial purpose without the purchase of a commercial license
# from OpenC3, Inc.
#
# The above copyright notice and this permission notice shall be included in all copies
# or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

This license is pretty straight forward, but the key is you can't use this code for any real work leading to a product (Formal Development, Integration and Test, or Operations) unless you switch to purchasing a commercial license.

## Commercial License

This license is a signed contract with OpenC3. It allows use of our code for a program under contractual terms where you do not have to follow the AGPLv3.

Generally we license to a specific project with terms that allow for unlimited users, and installs as needed by that project. Any code and plugins that you develop under the commercial license can be kept proprietary.

These licenses are sold as yearly subscriptions, or as a non-expiring perpetual license. We also offer site licenses, and licenses to support unlimited missions on a government framework architecture.

Of course with our commercial license, you also get all the extra functionality of our Enterprise product.

### Why you should buy a Commercial License

1. You want to save years and tens of millions of dollars developing the same functionality yourself.

2. You want all of the Enterprise functionality of COSMOS Enterprise Edition

   1. User Accounts
   2. Role Based Access Control
   3. LDAP Support
   4. Kubernetes Support
   5. Cloud Deployment Configurations
   6. The right to use CFDP and other Enterprise Only plugins
   7. Grafana Support
   8. Support from the COSMOS Developers
   9. Lots more - See our [Enterprise](https://openc3.com/enterprise) page

3. You don't want to follow the AGPLv3

   1. You want to keep the code and plugins you develop proprietary
   2. You don't want to publish an accessible link to your source code

4. You want to support the continued development and innovation of the COSMOS product

**_We appreciate all of our commercial customers. You make OpenC3 possible. Thank you._**

## FAQs

1. I see both Ball Aerospace & Technologies Corp as well as OpenC3, Inc in the copyright headers. What does this mean?

   OpenC3, Inc has an intellectual property agreement with BAE (formerly Ball Aerospace & Technologies Corp) which gives us the rights to commercialize the original work that we built at Ball Aerospace. Customers only need to purchase a commercial license from OpenC3.

1. What are the limits of the COSMOS Enterprise Edition? How many users can we have? How many times can it be installed?

   The COSMOS Enterprise Edition license has no user or installation limits.

1. How is the COSMOS Enterprise Edition license enforced?

   The COSMOS Enterprise Edition license is enforced through contract only without license managers or additional software controls.

1. How is the COSMOS Enterprise Edition license applied? Per company? Per program?

   COSMOS Enterprise Edition is typically licensed to a named mission or group. We also have site licenses, company licenses, and mission ops center licenses. Please contact us at sales@openc3.com for more information.

1. Do you license to foreign companies? How do you handle ITAR or the EAR?

   We have several international customers and are not subject to ITAR export controls. We are export controlled under the EAR via ECCN 5D002c1. We have a detailed writeup explaining this justification as well as a commodity classification document from the Department of Commerce. Please contact us at sales@openc3.com for more information.
