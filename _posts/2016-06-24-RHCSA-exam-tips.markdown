---
layout: post
title:  "Ten tips for RHCSA exam."
---

It took me 4 months to prepare for this exam, I read two books [1] [2] ruined tens VM's and made 36 commits to may sample repo.   

![RHCSA-Cert](/images/2016-06-24-RHCSA-exam-tips/OskarsG_RHCSA_pdf.png)

Here are some tips I can share:

1. Set up and practice on lab environment a lot. I mean literally a **loot**. Set up you lab environment with dedicated host machine one Centos 7 with Gnome desktop and create "master" VM (minimal installation without desktop) on KVM virtualization. For each task clone master VM and practice to perform tasks in a clean environment, remove VM.  Keep repeating tasks over and over until you know syntax from head and don't need to open man page for hints.

2. If you are away from your main lab environment use VirtualBox or Docker to practice small tasks. You can prepare master VM (with minimal installation) in VirtualBox and for each task repeat steps:  import VM , accomplish a task, destroy VM. Don't forget to set up [proper networking](https://github.com/ogavrisevs/RHCSA-RHCE-CodeExamples/blob/master/centos7_virtualbox.md) so you can ssh to VM after it's started.  With docker its even simpler `docker run -it centos` only step back -> installation is missing `man` package and by default all new packaged are skipping installation of man pages ([it can be fixed](https://github.com/ogavrisevs/RHCSA-RHCE-CodeExamples/blob/master/centos7_docker.md)).       

3. An even different keyboard can make an impact on your result, consider using "old-style" long press keyboards. ![hp-keyboard](/images/2016-06-24-RHCSA-exam-tips/hp-keyboard.png)

4. Develop a habit of checking every step / change you made. For example: `add user` -> `chek /etc/passwd file`, `made changes to fstab` -> `reboot machine, ensure partition is mounted`.

5. Set up ssh pub key authentification at the beginning of an exam. It will take extra time out of your exam but it will pay off, as you need to reboot your machine regularly to ensure your config is persistent.

6. Learn `man` command , there is no internet on exam host so your best friend will be `mandb && man -K topic ` and `catman && man -Kw key_term`.  

7. First thing in exam -> read all questions and pick all related to partitions and logical volumes first. If you make a mistake at beginning you will be able to revert your changes and start exam from scratch. If you make a mistake with partitions in middle-end of exam there will be no time to redo all tasks.

8. At the beginning of exam count number of tasks and divide to time you have (2.5h = 150 min.) it will give you average time on one task.  If you are spending on some task too much time (double of average time ) drop it, proceed with next question. Is important to finish all "easy tasks" as they will give "easy score points". You can always return to the hard question at the end of exam if time is left.

9. If time is left review your tasks and result. No matter how skilled you are it's easy to make mistakes on exam questions. Read every question twice and cerefully.

10. At end of your preparation take sample exams. Each book mentioned below contains two full exam samples.  Analyze your mistakes repeat topics until you feel confident to take exam.

References:
-----------
* [1] [Red Hat RHCA/RHCSE 7 Cert Guide: Red Hat Enterprise Linux 7 (by Sander van Vugt)](https://www.amazon.com/RHCSA-RHCE-Cert-Guide-Certification/dp/0789754053)
* [2] [RHCSA & RHCE Red Hat Enterprise Linux 7: Training and Exam Preparation Guide, Third Edition (by Asghar Ghori)](https://www.amazon.co.uk/RHCSA-RHCE-Red-Enterprise-Linux-ebook/dp/B00WFEIS0S)
* [Useful information regarding exam](https://www.certdepot.net/rhel7-rhcsa-ex200)
* [Notes and Task samples ](https://github.com/ogavrisevs/RHCSA-RHCE-CodeExamples)
* [Sander van Vugt youtube channel](https://www.youtube.com/channel/UComgXoI6pysmetOzuNH_TDQ)
