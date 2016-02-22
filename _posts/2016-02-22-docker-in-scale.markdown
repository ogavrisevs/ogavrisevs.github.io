---
layout: post
title:  "Building Docker containers in scale."
---

Introduction
-------------

I this article i will describe how to build highly available, highly scaleable build system for docker containers. We will use Jenkins to orchestrate docker build process, Jenkins itself will run in container on AWS ECS cluster. AWS ECS cluster will run on AWS Auto Scaling Group (ASG). We will spin-up Jenkins Slaves based on load demand. In front we will have AWS Route53 DNS name and ELB for redundancy. System architecture assumes any part of system can fail and will be restored in initial state automatically, also system will be able to respond on load spikes and will scale up / down build capabilities. We will host all infrastructure on AWS and provision it with CloudFormation template.

**Table Of Content:**

* TOC
{:toc}

Architecture overview
======================

![Architecture overview](/images/architecture.png)

As mentioned in front we will have AWS Route53 DNS name pointing to ELB. ELB itself will register all running containers within Jenkins Master. We will not use `sticky` sessions so each time user refresh page he can be redirected to any of containers running Jenkins Master. Containers will be served on AWS ECS cluster any failed containers will be restarted or rerun by AWS ECS scheduler. Actual build agents (EC2 instances) will be created and attached to Jenkins Master executor pool by `EC2` plugin. It allows to respond to any load demand (requests to build docker containers ) and scale-up or down within ~90 sec. (precise time depends on  AWS EC2 instance type ).      

 
Jenkins Master
===============
We will use Jenkins to orchestrate builds. Bacause we are looking to make system resilient there will be at least two Jenkins instances running. We will run Jenkins in container this way we will be able to quickly spin up more Jenkins instances if load increases also it will allow us to restore failed Jenkins instances. Running Jenkins is very simple, we can reuse official Jenkins docker image from [docker hub](https://hub.docker.com/_/jenkins/) :    

{% highlight bash %}
$ docker run -it -p 8080:8080 jenkins
{% endhighlight %}

We need to customize official image with multiple things:

1. Preinstall Jenkins plugins.
2. Preconfigure system ( authentification / executors / etc ).
3. Preconfigure plugins ( authentification keys for aws / cloud-init scripts for jenins slaves / etc.)
4. Default build jobs.  

Pre-Installing Jenkins plugins.
-------------------------------
When image with Jenkins will be executed to create container we can execute custom bash scripts.
One way of installing Jenkins plugins is to download plugin files `*.hpi` and place them in Jenkins plugin folder `/usr/share/jenkins/ref/plugins` before Jenkins applications is started. This is similar process as loading `*.jar` files to Java applications by providing lib path to `%CLASSLOADER`. Official Jenkins Dockerfile already provides this functionality by "plugins.sh" script and "plugins.txt" file. All we need to do is ensure booth files are stored in docker image and "plugins.sh" is executed when image is started:


`Dockerfile`
{% highlight text %}
. . .
COPY plugins.sh /usr/local/bin/plugins.sh
COPY plugins.txt /usr/local/bin/plugins.txt
RUN /usr/local/bin/plugins.sh /usr/local/bin/plugins.txt
. . .
{% endhighlight %}

`plugins.txt`
{% highlight text%}
job-dsl:1.42
github:1.16.0
  token-macro:1.12.1
  plain-credentials:1.1
  git:2.4.1
    scm-api:1.0
    git-client:1.19.1
    matrix-project:1.6
 . . .
{% endhighlight %}

Pre-Configure Jenkins Master and plugins .
------------------------------------------
Same way as we pre-install plugins we can execute `groovy` [initialization scripts](https://wiki.jenkins-ci.org/pages/viewpage.action?pageId=70877249) after Jenkins applications is started by placing script file in specific folder `$JENKINS_HOME/init.groovy.d/*.groovy`. Groovy script will allow us to manipulate internal state of Jenkins. Best part is in fact there is no permission control so we can change any configuration aspect of application as long as its not protected by Java itself. For example we can, limit executor count on Jenkins master :

`Dockerfile`
{% highlight text%}
COPY groovy/*.groovy /usr/share/jenkins/ref/init.groovy.d/
{% endhighlight %}

`master.groovy`
{% highlight groovy%}
import hudson.model.*;
import jenkins.model.*;
import hudson.plugins.ec2.*;

Thread.start {
    sleep 10000

    def jenkins = Jenkins.getInstance()

    jenkins.setLabelString("master")
    jenkins.setSlaveAgentPort(50000)
    jenkins.setNumExecutors(1)
}
{% endhighlight %}

Or restrict access to jenkins with password :

`master-credentials.groovy`
{% highlight groovy%}
import hudson.security.*;
import com.cloudbees.jenkins.plugins.sshcredentials.impl.*;
import com.cloudbees.plugins.credentials.*;
import com.cloudbees.plugins.credentials.domains.*;
import hudson.plugins.sshslaves.*;
import jenkins.model.*;
import hudson.model.*;

Thread.start {
    sleep 10000

    //Restrct access to jenkins
    hudson.security.HudsonPrivateSecurityRealm realm = new hudson.security.HudsonPrivateSecurityRealm(false)
    Jenkins.instance.setSecurityRealm(realm);
    Jenkins.instance.setAuthorizationStrategy(new FullControlOnceLoggedInAuthorizationStrategy());
    User user1 = realm.createAccount("admin", "password");
}
{% endhighlight %}

Pre-Configure Jenkins build jobs.
---------------------------------
To create build jobs we can use [job-dsl](https://wiki.jenkins-ci.org/display/JENKINS/Job+DSL+Plugin) plugin. This plugin allows to describe build jobs and all steps with simple DSL syntax. Its almost unlimited on what we can describe in job-dsl. To create jobs after Jenkins is started we will use all previous mentioned approaches together : load plugin, store goovy and dsl script in image, execute groovy to create seed job which contains job-dsl script and schedule seed job execution when Jenkins is started. For example to crate simple docker build job we need to modify:


`Dockerfile`
{% highlight text%}
COPY job-dsl/*.json /usr/share/jenkins/ref/init.groovy.d/job-dsl/
COPY groovy/*.groovy /usr/share/jenkins/ref/init.groovy.d/
{% endhighlight %}

`plugins.txt`
{% highlight text%}
job-dsl:1.42
{% endhighlight %}

`groovy/job-dsl.groovy`
{% highlight groovy%}
import hudson.model.*
import jenkins.model.*;
import javaposse.jobdsl.plugin.*;

Thread.start {
    sleep 10000
    def jenkins = Jenkins.getInstance()

    //Instantiate a new freestyle job
    def job = new FreeStyleProject(jenkins, "Seed")
    job.setAssignedLabel(null);

    job.setCustomWorkspace("/usr/share/jenkins/ref/init.groovy.d/job-dsl")
    def ExecuteDslScripts.ScriptLocation scriptlocationFileSys = new ExecuteDslScripts.ScriptLocation('false', "*.json", null);
    def ExecuteDslScripts executeDslScripts = new ExecuteDslScripts(scriptlocationFileSys, false, RemovedJobAction.IGNORE);

    job.buildersList.add(executeDslScripts)

    jenkins.add(job, job.getName());
    jenkins.reload()

    // Add job to queue
    def jobRef = jenkins.getItem(job.getName());
    jenkins.getQueue().schedule(jobRef,10);
}
{% endhighlight %}

`job-dsl/build-jenkins-master.json`
{% highlight groovy%}

freeStyleJob("BuildJenkinsMaster"){
  description ("BuildJenkinsMaster")
  label ("docker-191")
  scm {
    git {
      remote {
        name("jenkins-master-docker")
        url("https://github.com/ogavrisevs/JenkinsDockerCi.git")
      }
      branch("*/master")
    }
  }
  steps {
    shell ("\n"+
          "dt=`date +\"%y%m%d%H%M\"` \n"+
          "docker build -t jenkins-master:\${dt} ./jenkins-master-dsl \n"+
          "docker build -t jenkins-master:latest ./jenkins-master-dsl ")
  }
}
{% endhighlight %}


Jenkins Slaves
===============

As mentioned previous our goal is to build highly available and scalable system. Jenkins slaves and particular executors on slaves will be place where builds itself will happen. So we need to ensure there will be always enough executors regardless of load. Only way to achieve it is by dynamically provisioning new slaves and there down them when load is dropping. We will use [ec2 jenkins plugin](https://wiki.jenkins-ci.org/display/JENKINS/Amazon+EC2+Plugin) to spin-up  new instances.

`plugins.txt`
{% highlight text %}
ec2:1.29
node-iterator-api:1.5
{% endhighlight %}

Because we cannot afford any manual steps we will configure all plugin details with `groovy`. Tricky part is that no all details required by plugin we can hardcoded. For example AWS Security Group or AWS instance profile name are created by AWS CloudFormation template therefore resource name ( Physical Id ) consists of randomly generated suffix and CF stack name in prefix.

| Name in AWS CF template    | Name when resource is created               |
|    ( Logical Id )          | ( Physical Id )                             |
| -------------------------- | ------------------------------------------- |
| JenkinsSlaveSecurityGroup  | sg-381a425c                                 |
| JenkinsInstanceProfile     | jenkins-SlaveInstanceProfile-1D8KQ7015SNZ0  |

To get dynamic resource names we will query AWS API with [aws.cli](https://aws.amazon.com/cli/) and use [instance metadata service]( http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html). As example with AWS CLI we can fetch all security groups and search for one particular by name prefix:    

{% highlight groovy %}
def sec_groups = "aws --region eu-west-1 ec2 describe-security-groups --output json".execute().text
def securityGroup = jsonSlurper.parseText(sec_groups).SecurityGroups.GroupName.find { it.contains('JenkinsSlaveSecurityGroup') }
{% endhighlight %}

With instance metadata we can find AWS subnet id , we will reuse subnet id to create Jenkins slave in same subnet as Jenkins Master. This way we will ensure low network latency between slave and master but redundancy will not suffer because AWS ASG will ensure our Jenkins masters are created in multiple AWS AvailabilityZones.

{% highlight bash %}
curl http://169.254.169.254/latest/meta-data/network/interfaces/macs/${mac}/subnet-id/     
{% endhighlight %}


Because our main goal is to build docker images we will use [Amazon Linux for ECS]( http://docs.aws.amazon.com/AmazonECS/latest/developerguide/launch_container_instance.html) with preinstalled / preconfigured docker. Last peace missing is to provision new slave with default software  and configuration. For this task we will use [cloud-init]( https://cloudinit.readthedocs.org/en/latest/). Cloud-init is simple set of python scripts and utilities which can be used to install software dependencies and configure Linux system when its boots up. In our example we will install `git`, `java` and `aws-cli` :

{% highlight yaml %}
#cloud-config
repo_update: true
repo_upgrade: security

yum_repos:
  docker:
    baseurl: https://yum.dockerproject.org/repo/main/centos/6
    enabled: true
    failovermethod: priority
    gpgcheck: true
    gpgkey: https://yum.dockerproject.org/gpg
    name: Docker packages from dockerproject repo

packages:
  - htop
  - git
  - jq
  - aws-cli
  - java-1.8.0-openjdk
 {% endhighlight %}

Now all we need to do is set label to new slave executors and reuse this label in Jenkins jobs where particular docker build steps will be described. When new Jenkins job will be placed in job queue Jenkins will search for executor with particular label and if no executor will be found Jenkins will spin-up new slave to satisfy job dependency for label.  

![Jenkins Job Labels](/images/jenkins_labels.png)

Fault tolerance
================

Lets try to understand what type of disasters our system can survive.

Jenkins Master AWS EC2 instance is lost 
-----------------------------------

In this case AWS ASG will spot number of healthy instances is under threshold and will try to fix this by spinning up new AWS EC2 instances. Amount of time required to create new instance depends on EC2 instance type, AWS ASG settings and amount of provisioning needs to be applied. In our example its about 3-4 min. 

![AWS ASG](/images/aws_asg.png)

Jenkins Master is corrupted
----------------------------

If for some reason Jenkins Master stops working JVM process exits, container will change state from `RUNNING` to `STOPPED` ( for example JVM dies with not enough memory error, etc). AWS ECS scheduler will try to restore cluster state and spin up new containers. Also this applies if instance is lost and new EC2 instance  is created AWS ECS will start new container on new instance as soon as instance will join ECS cluster.    

![AWS ECS](/images/aws_ecs.png)

In setup with one ELB and at least two Jenkins masters, failure of one jenkins master instance or jenkins master container will not affect end user because ELB in doing constant health check for jenkins process running in container. These are simple HTTP request on `/` endpoint but as soon as health check will fail EBL will stop forwarding traffic. And as soon as new container is started and ELB health check gets `HTTP 200` response `live` traffic will be forwarded to new container.   

![ELB health check](/images/elb_health_check_s.png)

Jenkins Slave is lost
--------------------

In case of loosing Jenkins Slave ( can be due to network issues ) next time build job will appear in job queue and jenkins scheduler will not be able to find executor with required label jenkins master will ask `ECS` plugin to create required executors. Plugin will use authority by AWS IAM role ( provided by instance profile ) and will create new EC2 instance, as soon as `sshd` daemon on new instance will start to respond to requests jenkins master will ssh to instance preinstall required tools and will place instance to build executor pool. Time required to create new executors depends on instance type (size) and amount of provisioning required in our case its about ~90 sec.  

Links
=====

You can find sample project on GitHub [ogavrisevs/JenkinsDockerCi](https://github.com/ogavrisevs/JenkinsDockerCi). Feel free to clone and modify repo also any comments future requests are welcomed.  