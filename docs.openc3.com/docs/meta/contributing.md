---
title: Contributing
---

So you've got an awesome idea to throw into COSMOS. Great! This is the basic process:

1. Fork the project on Github
1. Create a feature branch
1. Make your changes
1. Submit a pull request

:::note Don't Forget the Contributor License Agreement!
By contributing to this project, you accept our Contributor License Agreement which is found here: [Contributor License Agreement](https://github.com/OpenC3/cosmos/blob/main/CONTRIBUTING.txt)

This protects both you and us and you retain full rights to any code you write.
:::

## Test Dependencies

To run the test suite and build the gem you'll need to install COSMOS's
dependencies. COSMOS uses Bundler, so a quick run of the `bundle` command and
you're all set!

```bash
\$ bundle
```

Before you start, run the tests and make sure that they pass (to confirm your
environment is configured properly):

```bash
\$ bundle exec rake build spec
```

## Workflow

Here's the most direct way to get your work merged into the project:

- Fork the project.
- Clone down your fork:

```bash
git clone git://github.com/<username>/openc3.git
```

- Create a topic branch to contain your change:

```bash
git checkout -b my_awesome_feature
```

- Hack away, add tests. Not necessarily in that order.
- Make sure everything still passes by running `bundle exec rake`.
- If necessary, rebase your commits into logical chunks, without errors.
- Push the branch up:

```bash
git push origin my_awesome_feature
```

- Create a pull request against openc3/cosmos:main and describe what your
  change does and the why you think it should be merged.

:::note Find a problem in the code or documentation?

    Please [create an issue](https://github.com/OpenC3/cosmos/issues/new/choose) on
    GitHub describing what we can do to make it better.

:::
