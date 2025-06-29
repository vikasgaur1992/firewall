pipeline {
    agent any

    environment {
        TF_DIR = "${WORKSPACE}/terraform"
        ANSIBLE_DIR = "${WORKSPACE}/ansible"
    }

    stages {
        stage('Terraform Init & Plan') {
            steps {
                dir("${TF_DIR}") {
                    sh 'terraform init'
                    sh 'terraform plan'
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir("${TF_DIR}") {
                    sh 'terraform apply'
                }
            }
        }

        stage('Run Ansible') {
            steps {
                dir("${ANSIBLE_DIR}") {
                    sh 'ansible-playbook -i inventory playbook.yml'
                }
            }
        }
    }
}
