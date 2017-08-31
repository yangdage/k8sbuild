# 工程信息
application="appname"

# 优先根据tag生成版本号，没有tag时取分支branch，没有git版本管理默认v1.0.0
version=`git describe --tags 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo v1.0.0`

# 镜像地址:registry/project/application

# 默认开发环境配置
context="dev"
registry="registry.xxx.com"
project="projectname"

# 正式环境配置
context_prod="prod"
registry_prod="registry.xxx.com"
project_prod="projectname"

# 新VPC集群正式环境配置
context_vpc="vpc"
registry_vpc="registry.xxx.com"
project_vpc="projectname"

# 指令
cmd=""

# 帮助说明
_help(){
cat <<- _EOF_

----------------------------帮助说明-----------------------------

       build        前端编译任务+生成服务器平台后端可执行文件

       docker       镜像build+镜像push

       kube         更新项目到集群，k8s配置目录：/k8s/$context

       status       查看项目运行状态

       deploy       部署任务组合（docker+kube）

       all          全部任务组合（build+docker+kube）


以下选项适用指令（docker，deploy，all）

       -c [context]    指定执行环境，例如：[./make -c dev/prod/vpc]

       -ns [namespace]    指定当前执行环境namespace，例如：[./make -ns default]

       -r [registry]   指定镜像host选项，例如：[./make all -r registry.xxx.com]

       -v [version]    指定版本号选项，例如：[./make all -v v1.1.0]

---------------------------------------------------------------------

_EOF_
}

# 错误中断处理
_check_err(){
	if [ $? -ne 0 ];then
		echo "error !!!!"
		exit 1
	fi
}

# 初始化执行环境
_init_context(){
    # 根据命令行参数判断是否切换环境
    if [ "$1"x = "$context"x ] || [ "$1"x = "$context_prod"x ] || [ "$1"x = "$context_vpc"x ];then
        kubectl config use-context $1
        context=$1
    else
        context=`kubectl config current-context`
        echo context:$context
    fi

    # 切换线上环境
    if [ "$context"x = "$context_prod"x ];then
        registry=$registry_prod
        project=$project_prod
    fi

    if [ "$context"x = "$context_vpc"x ];then
		registry=$registry_vpc
		project=$project_vpc
	fi
}

# 初始化namespace
_init_namespace(){
    # 根据命令行参数判断是否切换namespace
    namespace="$1"
    
    if [ "$namespace"x != ""x ];then
    	kubectl config set-context `kubectl config current-context` --namespace=$namespace > /dev/null
  	fi

	# 查询集群namespace等信息
  	kubectl config view|sed -n "/cluster: ${context}/,/name: ${context}/p"|sed "s/ \+//g"
}

# 前端编译任务+后端编译服务器平台可执行文件
_build(){
    gulp build
    _check_err
    GOOS=linux GOARCH=amd64 go build -o ./${application}
    _check_err
}

# 镜像构建+镜像push
_docker(){
    echo "start docker build [${registry}/${project}/${application}:${version}]......"
    docker build -t ${registry}/${project}/${application}:${version} .
    _check_err
    echo "start docker building......"
    docker push ${registry}/${project}/${application}:${version}
    _check_err
    # 更新配置文件镜像
    _chgimg
}

# 切换最新镜像
_chgimg(){
	img_old=`grep -o "image:.*" k8s/dev/deployment.yaml`
	if [ "$context"x = "prod"x ] || [ "$context"x = "vpc"x ];then
		img_old=`grep -o "image:.*" k8s/prod/deployment.yaml`
	fi

    echo "old image is:${img_old}"

    img_new="image: ${registry}/${project}/${application}:${version}"

    echo "new image is:${img_new}"

	if [ "$context"x = "prod"x ] || [ "$context"x = "vpc"x ];then
		sed -i "s#$img_old#$img_new#" k8s/prod/deployment.yaml
	else
		sed -i "s#$img_old#$img_new#" k8s/dev/deployment.yaml
	fi
    _check_err
}

# 项目部署
_kube(){
	if [ "$context"x = "prod"x ] || [ "$context"x = "vpc"x ];then
		kubectl delete -f k8s/prod/
		kubectl create -f k8s/prod/ --record
	else
		kubectl delete -f k8s/dev/
		kubectl create -f k8s/dev/ --record
	fi
    _status
}

# 项目部署状态
_status(){
	while(true)
	do
	    # 标识是否有没启动成功的pod
		flag=true
		# 获取应用所有pod状态
		pods=`kubectl get po|grep ${application}|awk '{print $1,$3,$5}'`

		if [ "$pods"x = ""x ] || [ ${#pods[@]} -eq 0 ];then
            echo "error:not found any pod !!!"
            exit 1
        fi

		let i=0
		# 打印行记录
		line=""

        echo "-------------------pods status---------------------"
		for data in $pods
		do
			line+="$data "
			let round=$i%3
			# 状态判断
			if [ $round -eq 1 ] && [ "$data"x != "Running"x ];then
				flag=false
			fi
			# 是否打印
			if [ $round -eq 2 ];then
				echo $line
				line=""
			fi
			let i+=1
		done
		echo "---------------------------------------------------"
		# 全部启动成功停止轮询状态
		if [ $flag = true ];then
		    echo "all pod is running..."
			exit 0
		fi
		sleep 2
	done
}

# 指令/选项参数解析
_init(){
    # 镜像地址参数
    registry_tmp=`echo $*|grep -oE '\-r[ ]+[^ ]*'|awk '{print $2}'`
    if [ "$registry_tmp"x != ""x ];then
        registry=$registry_tmp
    fi

    # 版本参数
    version_tmp=`echo $*|grep -oE '\-v[ ]+[^ ]*'|awk '{print $2}'`
    if [ "$version_tmp"x != ""x ];then
        version=$version_tmp
    fi

    # 执行环境参数
    context_tmp=`echo $*|grep -oE '\-c[ ]+[^ ]*'|awk '{print $2}'`
    if [ "context_tmp"x != ""x ];then
        _init_context $context_tmp
    fi

    # namespace参数
    namespace_tmp=`echo $*|grep -oE '\-ns[ ]+[^ ]*'|awk '{print $2}'`
    if [ "namespace_tmp"x != ""x ];then
        _init_namespace $namespace_tmp
    fi

    # 指令参数
    cmdarr=("build" "docker" "kube" "deploy" "status" "all")
    for OPT in $@
    do
        tmpcmd=`[[ "${cmdarr[@]/$OPT/}" != "${cmdarr[@]}" ]] && echo "$OPT"`
        if [ "$tmpcmd"x != ""x ];then
        	cmd=$tmpcmd
        fi
    done
}

_main(){
    _init $@

    case "$cmd" in
    "build")
    	_build;;
    "docker")
    	_docker;;
    "kube")
        _kube;;
    "deploy")
        _docker; _kube;;
    "status")
        _status;;
    "all")
        _build; _docker; _kube;;
    *)
        _help
    esac
}

_main $@