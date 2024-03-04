---
layout: post
title:  "Process isolation in docker."
---

![Docker banner](/images/2016-07-11-isolation-in-docker/docker-banner2.jpg)

Introduction.
------------
{:.no_toc}

Starting from the first-day docker promised us [strong guarantees of isolation](https://github.com/docker/docker/tree/7cc0a07524cdc80a146a8f9ea74cfb59b1f6c414). In this blog post, I will test this promises. I will us different cli tools to generate CPU/RAM/DISK load in the container and investigate what impact it makes on host machine. Also, I will look for ways how can we limit resource usage .

__Table Of Content__

* TOC
{:toc}

Lab environment
---------------
I will use `aws.ec2.t2.medium` instance with 2x CPU

```
# grep "model name" /proc/cpuinfo
model name    : Intel(R) Xeon(R) CPU E5-2676 v3 @ 2.40GHz
model name    : Intel(R) Xeon(R) CPU E5-2676 v3 @ 2.40GHz
```

36GB RAM and 0MB Swap:

Instance is provisioned with official Centos7 image ([ami-7abd0209](https://aws.amazon.com/marketplace/pp/B00O7WM7QW)). Docker is installed from official yum repo (https://yum.dockerproject.org/repo/main/centos/7/ ) on version `1.11.2`. As storage driver for `docker-engine` we will use `devicemapper`(loop) .

As instance storage we will use `EBS.GP2`, 8GB drive with 100 IOPS.

CPU usage.
----------

To generate CPU load I will use bash tool [stress](http://linux.die.net/man/1/stress).  Lets create Centos6 based container with `stress` installed inside.

{% highlight bash %}
$ sudo vim Dockerfile.stress
{% endhighlight %}

{% highlight docker %}
FROM centos:6

RUN yum install -y epel-release
RUN yum install -y stress

ENTRYPOINT ["/usr/bin/stress", "--verbose"]
{% endhighlight %}

{% highlight bash %}
$ sudo docker build -f Dockerfile.stress -t stress .
{% endhighlight %}

Now lets try to use as much CPU as possible with 4x workers and time limit 10s.

{% highlight bash %}
$ sudo docker run --rm --name stress stress --cpu 4 --timeout 10
{% endhighlight %}

{% highlight bash %}
CONTAINER   CPU %     MEM USAGE / LIMIT     MEM %  
stress      199.24%    2.953 MB / 3.706 GB   0.08%  
{% endhighlight %}

As we can see by default docker is not limiting CPU usage for process inside docker container.

Lets try to limit CPU usage by allowing to use only one CPU unit by setting `--cpuset-cpus=0`.

{% highlight bash %}
$ sudo docker run --rm --name stress --cpuset-cpus="1" stress --cpu 4 --timeout 10
{% endhighlight %}

{% highlight bash %}
CONTAINER           CPU %               MEM USAGE / LIMIT     MEM %
stress              100.50%             3.084 MB / 3.706 GB   0.08%
{% endhighlight %}

As we can see the process is able to utilize only one CPU unit.

Let's image different scenario, for example, we want to run 3 containers two containers have lower priority, one container demands dedicated higher CPU usage. We can solve this by setting container CPU priority with `--cpu-shares`.

{% highlight bash %}
$ sudo docker rm -f 1cpu half_cpu11 half_cpu22
$ sudo docker run -d --name 1cpu --cpu-shares="512" stress --cpu 4  --timeout 20
$ sudo docker run -d --name half_cpu11 --cpu-shares="256" stress --cpu 4 --timeout 20
$ sudo docker run -d --name half_cpu22 --cpu-shares="256" stress --cpu 4 --timeout 20
{% endhighlight %}

{% highlight bash %}
$ sudo docker stats 1cpu half_cpu11 half_cpu22
CONTAINER     CPU %   MEM USAGE / LIMIT      MEM %
1cpu          99.89%   2.953 MB / 3.706 GB   0.08%
half_cpu11    49.43%   2.966 MB / 3.706 GB   0.08%
half_cpu22    49.29%    2.97 MB / 3.706 GB   0.08%
{% endhighlight %}

As we can see on container occupies 100% of one CPU unit and two container uses half each of other CPU, so far everything as expected.

Memory
-------
By default, docker will set the memory limit to amount of physical memory.

{% highlight bash %}
$ sudo docker run --rm --name stress  stress --vm 3 --vm-bytes 256M --timeout 10
{% endhighlight %}

We can limit memory usage by setting `--memory` arg. With this example, we will try to allocate 256MB for each of 3x workers (768MB total). Same time we will limit available memory for container to 512MB

{% highlight bash %}
sudo docker run --rm --name stress --memory 512m \
  stress --vm 4 --vm-bytes 256M --timeout 10
 . . .
stress: FAIL: [1] (415) <-- worker 6 got signal 9
stress: FAIL: [1] (415) <-- worker 5 got signal 9
. . .
{% endhighlight %}

From log output we can see process inside container was killed by reciving `SIGKILL` [link](https://en.wikipedia.org/wiki/Unix_signal#POSIX_signals) signal, in system logs we can find following entries:

{% highlight logs %}
kernel: memory: usage 524188kB, limit 524288kB, failcnt 246
kernel: memory+swap: usage 524188kB, limit 1048576kB, failcnt 0
kernel: Memory cgroup out of memory: Kill process 23681 (stress) kernel: Killed process 23681 (stress) total-vm:268716kB, anon-rss:247248kB, file-rss:0kB
{% endhighlight %}

`Stress` process was killed by kernel because we exceeded memory and there is no swap memory on instance.

Lets try to add 2G swap and repeat test.

{% highlight bash %}
$ sudo dd if=/dev/zero of=/swapfile bs=1024 count=2097152
$ sudo mkswap /swapfile
$ sudo chmod 600 /swapfile
$ sudo swapon /swapfile
{% endhighlight %}

{% highlight bash %}
$ free -h
        total  used  free  shared  buff/cache   available
Mem:     3.5G  127M  375M  16M        3.0G        3.1G
Swap:    2.0G  0B    2.0G
{% endhighlight %}

{% highlight bash %}
$ sudo docker run --name stress-mem --memory 512m \
  stress --vm 3 --vm-bytes 256M --timeout 10
{% endhighlight %}

By default docker sets swap memory as double size of physical memory and container can use full amount of swap space. We can check it by inspecting container :

{% highlight bash %}
$ sudo docker inspect --format= \
 "Memory:{ {.HostConfig.Memory} }, \
  MemorySwap:{ {.HostConfig.MemorySwap} }, \
  MemorySwappiness:{ {.HostConfig.MemorySwappiness} }"\
  stress-mem

$ Memory:536870912, MemorySwap:1073741824, MemorySwappiness: -1
{% endhighlight %}

{% highlight bash %}
$ sudo smem -k -t -p -P stress
  PID User     Command                         Swap      USS      PSS      RSS
 4147 root     /usr/bin/stress --verbose -    80.0K        0     1.0K     8.0K
 4091 root     sudo docker run --rm --name        0   676.0K   885.0K     2.7M
 4092 root     docker run --rm --name stre        0     4.8M     8.4M    12.8M
 4156 root     /usr/bin/stress --verbose -    73.3M    77.7M    77.7M    77.7M
 4158 root     /usr/bin/stress --verbose -    86.6M   137.4M   137.4M   137.4M
 4157 root     /usr/bin/stress --verbose -    81.5M   174.6M   174.6M   174.6M
-------------------------------------------------------------------------------
                                             241.5M   400.8M   405.5M   415.0M
{% endhighlight %}

In our example it means `stress` process will try to use 768MB memory and kernel will allow to use 512MB on physical memory and 256MB on swap space

Another approach to control memory is to forbid kernel to kill process when it exeeds memory limits with `--oom-kill-disable`. This is highly dangerous as if there is a memory leak in process running in a container we can occupy all memory on host machine and effectively mess up whole hot.

{% highlight bash %}
$ sudo docker run --rm --name stress --memory 512m \
 --memory-swap 1g --memory-swappiness=50 \
 --oom-kill-disable \
 stress --vm 5 --vm-bytes 256M --timeout 10
{% endhighlight %}

In this example we will use 512 Mb from physical memory, half of swap memory (512 Mb) and we will disable kernel to kill process when it exceeds memory limit.

Disk
------

When we speak about disk and docker we need to separate two things. On thing is how much space we can occupy on disk and another thing how much bandwidth (i/o and read/writes per sec.) we can use. By default, there are not limits one bandwidth usage in docker (in terms of reads/writes).

#### Disk usage (base device) ####

As we know (if not specified else) data in container is not persistent, amount of data you can store in such container depends on disk drives docker is configured to use. By default on Centos7 device driver is `devicemapper`. And by default `base device` size is about ~ 10GB.

{% highlight bash %}
$ sudo docker info | grep "Base Device Size"
 Base Device Size: 10.74 GB
{% endhighlight %}

{% highlight bash %}
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1      8.0G  4.2G  3.9G  52% /
devtmpfs        1.9G     0  1.9G   0% /dev
tmpfs           1.8G     0  1.8G   0% /dev/shm
tmpfs           1.8G   17M  1.8G   1% /run
{% endhighlight %}

It's funny if we take to account my system has only 8GB disk attached. Basically any container with heavy disk usage can corrupt my server. Let's not test it, instead, lets set `base device` size to 2GB.

{% highlight bash %}
$ vim /usr/lib/systemd/system/docker.service
  ExecStart=/usr/bin/docker daemon \
    -H fd:// --storage-opt dm.basesize=2G
{% endhighlight %}

{% highlight bash %}
$ sudo systemctl stop docker
$ sudo rm -rf /var/lib/docker
$ sudo systemctl start docker
{% endhighlight %}

{% highlight bash %}
$ sudo docker info | grep "Base Device Size"
  Base Device Size: 2.147 GB
{% endhighlight %}

Now lets try to write some files inside container.

{% highlight bash %}
$ sudo docker run --rm --name fio centos:7 \
    dd if=/dev/zero of=test bs=64k count=160k \
    conv=fdatasync

dd: error writing 'test': No space left on device
28763+0 records in
28762+0 records out
1884962816 bytes (1.9 GB) copied, 21.7735 s, 86.6 MB/s
{% endhighlight %}

In this example we are writing 160'000 file each with size 64KB. As expected kernel killed process because it tried to ocuppay more space than allowed (2.147 GB)

By the way, `devicemapper` (loop) is not recommended as docker storage driver for production systems, check docker documentation for [recommended production drivers](https://docs.docker.com/engine/userguide/storagedriver/selectadriver/) .


#### Bandwidth limitation ####

To test read/write and io performance we will use [fio](http://linux.die.net/man/1/fio) bash tool. Lets start by creating images with pre-installed `fio`.

{% highlight bash %}
$ vim Dockerfile.fio
{% endhighlight %}

{% highlight dockerfile %}
FROM centos:7

RUN yum install -y epel-release
RUN yum install -y fio

ENTRYPOINT ["/usr/bin/fio"]
{% endhighlight %}

{% highlight bash %}
$ sudo docker build -f Dockerfile.fio -t fio .
{% endhighlight %}

There is only two things we can limit when it comes to bandwidth -> io count per second and bytes per second. Let try test io limitation by setting `device-write-iops` and `device-read-iops`.

{% highlight bash %}
$ docker run --rm --name fio --device-write-iops /dev/loop0:100 \
  --device-read-iops /dev/loop0:100 fio --ioengine=libaio \
  --rw=randrw --runtime=10 --size=32M --bs=4k --iodepth=16 \
  --numjobs=4 --name=fio_rw_test --group_reporting

read : io=4020.0KB, bw=411236B/s, iops=100, runt= 10010msec
write: io=3532.0KB, bw=361315B/s, iops=88, runt= 10010msec
{% endhighlight %}

In this example, we are trying to read/write 4KB blocks of data to file on disk with 4x parallel workers. We are also limiting execution to 10 sec. and 32MB max data. As we can see from report iops count for read is exactly 100 and 88 for write. Also total amount of data we managed to read + write is ~7 MB.

Its interesting to so can we write more data (potentially full-fill disk) with bigger block sizes. Let's try to increase block size and see how many data we will be able to write to disk.

{% highlight bash %}
docker run --rm --name fio --device-write-iops /dev/loop0:100 \
 --device-read-iops /dev/loop0:100 fio --ioengine=libaio \
 --rw=randrw --runtime=10 --size=32M --bs=32k --iodepth=16 \
 --numjobs=4 --name=fio_rw_test --group_reporting
{% endhighlight %}

{% highlight bash %}
read : io=32160KB, bw=3212.9KB/s, iops=100, runt= 10010msec
write: io=28512KB, bw=2848.4KB/s, iops=89, runt= 10010msec
{% endhighlight %}

As we can see from report we managed to read 32 MB and write 28 MB of data. It means its not enough of limiting iops count because some "neasty" process in container can full-fill disk by increasing write block size.

Lets try to limit writes by setting write bytes per/sec with `--device-write-bps` and reads with  `--device-read-bps`.

{% highlight bash %}
docker run --rm --name fio --device-write-bps /dev/loop0:1m --device-read-bps /dev/loop0:1m fio  --ioengine=libaio --rw=randrw --runtime=10 --size=32M --bs=4k
--iodepth=16 --numjobs=4 --name=fio_rw_test --group_reporting
{% endhighlight %}

{% highlight bash %}
read : io=10360KB, bw=1025.8KB/s, iops=256, runt= 10100msec
write: io=9252.0KB, bw=938024B/s, iops=229, runt= 10100msec
{% endhighlight %}

As we can see we effectivly restricted an amount of data container can read/write. Other important aspect of disk bandwidth is how we specify device we assign limits. In the example device is `/dev/loop0` this device in case docker storage driver `devicemapper` (with loop) is responsible for storing actual data we need to consider of limiting also a device which stores metadata (`/dev/loop1`). And finally if we are using volumes in container we can directly write to host filesystem (depends on how we use volumes). In this case restrictions on loop, devices will not help us and we need to limit usage of host storage device (`/dev/xvda` etc).

{% highlight bash %}
docker run --rm --name fio --device-write-bps /dev/xvda:1m \
  --device-read-bps /dev/xvda:1m -v /fio_dir fio \
  --ioengine=libaio --rw=randrw --runtime=10 --size=32M \
  --bs=4k --iodepth=16 --numjobs=4 --name=fio_rw_test \
  --directory=/fio_dir --group_reporting
{% endhighlight %}

{% highlight bash %}
read : io=10252KB, bw=1025.1KB/s, iops=256, runt= 10001msec
write: io=8900.0KB, bw=911268B/s, iops=222, runt= 10001msec
{% endhighlight %}

Conclusion
----------

As we saw from multiple example docker provides a rich set of tools to restrict resource usage in `docker-engine` and this way atchieve true process isolation on a particular linux machine. We can limit resources usage by allowing to use only particular device (first CPU unit, amount of RAM, partition on disk) also we can limit resources usage time / priority   (high cpu priority container, dedicated read/write on RAM no swap usage, iops  and byte/sec on particular storage device). Also, we notice that by default resource limits (isolation) is weak we can easily overuse any resource, as any other resource on linux machine ( without dedicated configured `seLinux`, user permissions, `lvm` , etc). And it's fine because we are using docker in "clean" way without any wrapper/ schedulers/ clusters in real production environment `docker-engine` will be controlled by a scheduler (Mesos, Kubernetes, AWS.ECS, Docker Swarm, etc. ) and it will this system responsaibiality to control and restrict resource usage.
