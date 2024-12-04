# Genestack Secure Development Practices

Genestack is a complete operation and deployment ecosystem for OpenStack services that heavily utilizes cloud native application like
Kubernetes. While developing, publishing, deploying and running OpenStack services based on Genestack we aim to ensure that our engineering teams follow
security best practices not just for OpenStack components but also for k8s and other cloud native applications used within the Genestack ecosystem.

This security primer aims to outline layered security practices for Genestack, providing actionable security recommendations at every level to mitigate
risks by securing infrastructure, platform, applications and data at each layer of the development process.
This primer emphasizes secure development practices that complement Genestack's architecture and operational workflows.


## Layered Security Approach

Layered security ensures comprehensive protection against evolving threats by addressing risks at multiple levels. The approach applies security measures
to both physical infrastructure and also provides security focus to the development of the application itself. The aim is to minimize a single point
of failure compromising the entire system. This concept aligns with the cloud native environments by catagorizing security measures across the lifecycle and stack of the cloud native technologies.

The development team follow a set of practices for Genestack: Rackspace OpenStack Software Development Life Cycle (Rax-O-SDLC). The SDLC practice aims to produce
software that meets or exceeds customer expectation and reach completion within a time and cost estimate. SDLC process is divided into six distinct phases: `Scope`, `Implement`,
`Document`, `Test`, `Deployment` and `Maintain`.

For each of the above stages fall within the security guidelines from CNCF that models security into four distince phases.

Security is then injected at each of these phases:

1. **Develop:** Applying security principles during application development

2. **Distribute:** Security practices to distribute code and artifacts

3. **Deploy:** How to ensure security during application deployment

4. **Runtime:** Best practices to secure infrastructure and interrelated components


Lets look at it from OpenStack side of things. We want to see security across:

1. **Infrastructure:** Both physical and virtual resources

2. **Platform:** Services that support workloads

3. **Applications:** Containerized workloads and instances that run the services

4. **Data:** Security of data at rest and in transit


CNCF defines its security principles as:

1. Make security a design requirement

2. Applying secure configuration has the best user experience

3. Selecting insecure configuration is a conscious decision

4. Transition from insecure to secure state is possible

5. Secure defaults are inherited

6. Exception lists have first class support

7. Secure defaults protect against pervasive vulnerability exploits

8. Security limitations of a system are explainable


These guidelines can be adopted to have a secure foundation for Genestack based cloud.
