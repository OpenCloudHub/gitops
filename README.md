<a id="readme-top"></a>

<!-- PROJECT LOGO & TITLE -->

<div align="center">
  <a href="https://github.com/opencloudhub">
  <picture>
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-light.svg">
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-dark.svg">
    <!-- Fallback -->
    <img alt="OpenCloudHub Logo" src="https://raw.githubusercontent.com/opencloudhub/.github/main/assets/brand/assets/logos/primary-logo-dark.svg" style="max-width:700px; max-height:175px;">
  </picture>
  </a>

<h1 align="center">Gitops</h1>

<!-- SORT DESCRIPTION -->

<p align="center">
    ArgoCD gitops configuration for the cluster.<br />
    <a href="https://github.com/opencloudhub/.github"><strong>Explore the organization »</strong></a>
  </p>

<!-- BADGES -->

<p align="center">
    <a href="https://github.com/opencloudhub/.github/graphs/contributors">
      <img src="https://img.shields.io/github/contributors/opencloudhub/.github.svg?style=for-the-badge" alt="Contributors">
    </a>
    <a href="https://github.com/opencloudhub/.github/network/members">
      <img src="https://img.shields.io/github/forks/opencloudhub/.github.svg?style=for-the-badge" alt="Forks">
    </a>
    <a href="https://github.com/opencloudhub/.github/stargazers">
      <img src="https://img.shields.io/github/stars/opencloudhub/.github.svg?style=for-the-badge" alt="Stars">
    </a>
    <a href="https://github.com/opencloudhub/.github/issues">
      <img src="https://img.shields.io/github/issues/opencloudhub/.github.svg?style=for-the-badge" alt="Issues">
    </a>
    <a href="https://github.com/opencloudhub/.github/blob/main/LICENSE">
      <img src="https://img.shields.io/github/license/opencloudhub/.github.svg?style=for-the-badge" alt="License">
    </a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->

<details>
  <summary>📑 Table of Contents</summary>
  <ol>
    <li><a href="#features">Features</a></li>
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#project-structure">Project Structure</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgements">Acknowledgements</a></li>
  </ol>
</details>

<!-- FEATURES -->

<h2 id="features">✨ Features</h2>

<!-- GETTING STARTED -->
# TODO: preinstall script with cloud provider kind and yq

<h2 id="getting-started">🚀 Getting Started</h2>
1. Clone this repository and cd into the directory:
   ```bash
   git clone https://github.com/opencloudhub/gitops.git
   cd opencloudhub
   ```

2. Create access token for the repo used by ArgoCD ( Can use GithubApp as well )
1. Create folder to store shh key

````
```bash
mkdir -p ~/.ssh/opencloudhub
```
````

2. Create asynchronous deploy token without passphrase

```bash
ssh-keygen -t ed25519 -C "argocd_gitops@opencoudhub.com" -f ~/.ssh/opencloudhub/argocd_gitops_ed25519 -N ""


```

3. Get public key and add it as deploy token to gh repo:

```bash
echo "Public Key:" && cat ~/.ssh/opencloudhub/argocd_gitops_ed25519.pub
```

- Navigate to Github repo
- Go to settings
- Under Security Section: Deploy Keys > Add Key
  - title: argocd_gitops_ed25519
  - allow write access: true

3. Update the .env file

4. Start dev bash scripts/bootstrap/local-development/start-dev.sh

### Prerequisites

### Usage

<h2 id="project-structure">📁 Project Structure</h2>

```
.
├── CODE_OF_CONDUCT.md          # Community guidelines
├── CONTRIBUTING.md             # Contribution guidelines
├── SECURITY.md                 # Security policies
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->

<h2 id="contributing">👥 Contributing</h2>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

<h2 id="license">📄 License</h2>

Distributed under the Apache 2.0 License. See [LICENSE](/LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->

<h2 id="contact">📬 Contact</h2>

Organization Link: [https://github.com/OpenCloudHub](https://github.com/OpenCloudHub)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ACKNOWLEDGEMENTS -->

<h2 id="acknowledgements">🙏 Acknowledgements</h2>

Share links or references to useful resources:

- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) - The foundation for this README design

<p align="right">(<a href="#readme-top">back to top</a>)</p>

______________________________________________________________________

<div align="center">
  <h3>🌟 Follow the Journey</h3>
  <p><em>Building in public • Learning together • Sharing knowledge</em></p>

<div>
    <a href="https://opencloudhub.github.io/docs">
      <img src="https://img.shields.io/badge/Read%20the%20Docs-2596BE?style=for-the-badge&logo=read-the-docs&logoColor=white" alt="Documentation">
    </a>
    <a href="https://github.com/orgs/opencloudhub/discussions">
      <img src="https://img.shields.io/badge/Join%20Discussion-181717?style=for-the-badge&logo=github&logoColor=white" alt="Discussions">
    </a>
    <a href="https://github.com/orgs/opencloudhub/projects/4">
      <img src="https://img.shields.io/badge/View%20Roadmap-0052CC?style=for-the-badge&logo=jira&logoColor=white" alt="Roadmap">
    </a>
  </div>
</div>

<!-- MARKDOWN LINKS & IMAGES -->
