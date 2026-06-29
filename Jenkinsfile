pipeline {
    agent any

    environment {
        DOCKER_USERNAME  = "kartikmehta"
        DOCKER_CREDENTIALS_ID = "docker-creds"

        IMAGE_NAME = "${DOCKER_USERNAME}/squareops-assessments"
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
    }

    stages {

        stage('Checkout Code') {
            steps {
                git url: "https://github.com/KartikMehtaa/squareops-devops-assignment.git", branch: "main";
                echo "Code downloaded successfully"
            }
        }

        stage('Lint Python Code') {
    steps {
        dir('vote') {
            sh '''
                pip install flake8 --quiet --break-system-packages
                export PATH=$PATH:/var/lib/jenkins/.local/bin
                flake8 . --max-line-length=120 --exclude=__pycache__
                echo "No errors found in Python code"
            '''
        }
    }
}
        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} vote/
                    echo "Image built: ${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.DOCKER_CREDENTIALS_ID,
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        echo "Image pushed successfully"
                    '''
                }
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    docker run -d --name vote-test -p 5000:80 ${IMAGE_NAME}:${IMAGE_TAG}
                    sleep 10
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000)
                    echo "App returned HTTP status: ${STATUS}"
                    if [ "$STATUS" != "200" ]; then
                        echo "TEST FAILED - App did not return 200"
                        exit 1
                    fi
                    echo "TEST PASSED"
                '''
            }
        }
    }

    post {
        always {
            sh '''
                docker stop vote-test 2>/dev/null || true
                docker rm   vote-test 2>/dev/null || true
            '''
            echo "Cleanup done"
        }
        success {
            echo "Pipeline PASSED - image is on Docker Hub"
        }
        failure {
            echo "Pipeline FAILED - check the red stage above"
        }
    }
}
