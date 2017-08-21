FROM reg.aliyun.so/library/centos:7
MAINTAINER "yangdage <qiyang@hyx.com>"

RUN rm /etc/localtime && ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
ADD ./appname /usr/local/appname
RUN chmod +x /usr/local/appname/appname

WORKDIR /usr/local/appname
