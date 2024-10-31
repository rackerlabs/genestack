# Contributing

Welcome!  Thank you for wanting to contribute to Genestack!

When contributing to this repository, please first discuss the change you wish to make via issue,
email, or any other method with the owners of this repository before making a change. However, if
you see a problem, feel free to fix it.

## Branching

1. Please fork the repository and create a feature/modification branch.  GitHub
   [makes this easy](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-and-deleting-branches-within-your-repository).
2. **Test your changes!** -- If you are making changes to the general Genestack repo, do a clean build
   from scratch.  If you are changing the docs, then rebuild the docs from scratch and lint your
   Markdown.  (You can use [this](https://gist.github.com/OpenStackKen/846a045ecfe74f1895d5c93cbb2fe801)
   to simply check for trailing spaces, or you can go full [Markdown Lint](https://github.com/igorshubovych/markdownlint-cli)
   on it.
3. Once your branch builds, make sure you're caught-up to main and rebase if necessary.

## Commits

1. We are trying to use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for our
   repository.  This allows us to have an easy way to tell what each commit is trying to achieve, and
   will speed reviews.
2. This [cheatsheet](https://gist.github.com/OpenStackKen/5c99d4a5d69085718a0d3d0bfc6b2231) can be
   helpful to keep around to use to make commits easy.
3. Keep your changes atomic.  Smaller commits centered around specific changes are easier to merge than
   big "jumbo" commits that touch things in many places.
4. Commits need to be [signed](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)
    and will need to show up as [verified](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) in GitHub.

## Pull Request Process

1. Ensure any install or build dependencies are removed before the end of the layer when doing a
   build.
2. Make sure you haven't added any extraneous files to the repository (secrets, .DS_Store, etc.) and
   double-check .gitignore if you have a new type of change.
3. Update the README.md / Wiki with details of changes to the interface, this includes new environment
   variables, exposed ports, useful file locations and container parameters.
4. You may merge the Pull Request in once you have the sign-off of one other developer, or if you
   do not have permission to do that, you may request the reviewer to merge it for you.
