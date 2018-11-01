with import <nixpkgs>{};

let
  minikube = callPackage ./nix/minikube/default.nix {
    inherit (darwin.apple_sdk.frameworks) vmnet;
  };

  kubeval = callPackage ./nix/kubeval {};
in

stdenv.mkDerivation rec {
  name = "intro-to-k8s-env";

  # These are tools that will be available inside the shell
  buildInputs = [
    coreutils
    kubectl
    minikube
    kubernetes-helm
    kubeval
  ];

  # Commands that will run when the shell is started
  shellHook = ''
    function prefixwith() {
      local prefix="$1"
      shift
      "$@" > >(sed "s/^/$prefix: /") 2> >(sed "s/^/$prefix (err): /" >&2)
		}

    function ensure-host-entry() {
      hosts_entry="$(minikube ip) $LOCAL_DOMAIN"

      if ! grep -q "$hosts_entry" /etc/hosts; then
        echo hosts entry for ingress not found, adding \'$hosts_entry\' to your hosts file;
        echo $hosts_entry | sudo tee -a /etc/hosts
      fi
    }

    function setup-helm() {
      echo "Apply Helm Tiller configuration"
      prefixwith [kubectl] ${kubectl}/bin/kubectl apply -f rbac-config.yaml

      echo "Initializing Helm & Tiller"
      prefixwith [helm] ${kubernetes-helm}/bin/helm init --service-account tiller
    }

    function ensure-permissions() {
      echo "Checking if hyperkit driver is owned by root"

      if ! stat -c %U:%G ${minikube}/bin/docker-machine-driver-hyperkit | grep -q root:wheel ; then
        sudo chown root:wheel ${minikube}/bin/docker-machine-driver-hyperkit
      fi;

      echo "Checking if hyperkit driver has setuid set"

      if [[ ! -u ${minikube}/bin/docker-machine-driver-hyperkit ]]; then
        sudo chmod u+s ${minikube}/bin/docker-machine-driver-hyperkit
      fi;
    }

    function minikube {
      args=("$@")

      if [[ ''${args[0]} == "start" ]]; then
        echo "Running checks before starting"

        # Checks
        ensure-permissions
        prefixwith [minikube] ${minikube}/bin/minikube $@
        setup-helm
        ensure-host-entry
      else
        # just run minikube
        ${minikube}/bin/minikube $@
      fi

    }

    # loads settings for your shell, check it out!
    source .envrc
  '';
}
