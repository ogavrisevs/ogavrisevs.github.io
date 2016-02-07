---
layout: post
title:  "How to build 10k cointainers / h .  "
date:   2016-02-07 23:53:31 +0000
categories: jekyll update
---

Introduction:

I this article i will describe how to build highly available, highly scaleable build system for docker container. We will use Jenkins to orchestrate build process, Jenkins itself will run in container on AWS.ECS cluster. AWS.ECS cluster will run on autoscaling group. We will spin-up Jenkins Slaves based on load demand. In front we will have AWS.Route53 DNS name and ELB for redundancy. System architecture assumes any part of system can fail and will be restored in initial state automatically, also system will be able to respond on load spikes and will scale up / down build capabilities. We will host all infrastructure on AWS and provision it with CloudFormation template.

Table Of Content:

* TOC
{:toc}


Architecture overview
======================

![Alt text](/images/architecture.png "Architecture overview")





Jenkins Master
===============
We will use Jenkins to orchestrate builds. Bacause we are looking to make system resilient there will be atlast two Jenkins instances running. We will run Jenkins in container this way we will be able to quickly spin up more Jenkins instances if load increases also it will allow us to restore failed Jenkins instances. Running Jenkins is very simple, we can reuse official Jenkins docker image from [docker hub](https://hub.docker.com/_/jenkins/) :    

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
One way of installing Jenkins plugins is to download plugin files `*.hpi` and place them in Jenkins plugin folder `/usr/share/jenkins/ref/plugins` before Jenkins applications is started. This is similar process as loading `*.jar` files to Java applications by providing lib path to `%CLASSLOADER`. Officall Jenkins Dockerfile already provides this functionality by "plugins.sh" script and "plugins.txt" file. All we need to do is ensure booth files are stored in docker image and "plugins.sh" is executed when image is started:


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
To create build jobs we can use [job-dsl](https://wiki.jenkins-ci.org/display/JENKINS/Job+DSL+Plugin) plugin. This plugin allows to describe build jobs and all steps with simple DSL syntax. Its almost unlimited on what we can describe in job-dsl. To create jobs after Jenkins is started we will use all previous mentioned approaches together : load plugin, store goovy and dsl script in image, execute groovy to create seed job which contains job-dsl script and schedule seed job execution when Jenkins is started. For example to crate simple docker build job:


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
