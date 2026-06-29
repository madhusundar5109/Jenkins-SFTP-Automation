pipeline {
    agent { label 'built-in' }

    options {
        disableConcurrentBuilds()        
        skipDefaultCheckout()            
    }

    parameters {
        string(name: 'CHANGED_FILE', defaultValue: '', description: 'Absolute path of the file to sync')
    }

    environment {
        REMOTE_HOST   = "<IP or hostname address of Remote host>"
        REMOTE_FOLDER = "<SFTP server Remote folder absolutre path>"
    }

    stages {
        stage('Validate') {
            steps {
                script {
                    if (!params.CHANGED_FILE?.trim()) {
                        error("No file specified. This job must be triggered by the file watcher.")
                    }
                    echo "Push event received for: ${params.CHANGED_FILE}"
                }
            }
        }

        stage('Transfer File') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: '<Credentials ID in Jenkins>',
                        usernameVariable: 'SSH_USER',
                        passwordVariable: 'SSH_PASS'
                    )
                ]) {
                    sh '''
                        sshpass -p "$SSH_PASS" scp \
                            -o StrictHostKeyChecking=no \
                            "$CHANGED_FILE" \
                            "$SSH_USER@$REMOTE_HOST:$REMOTE_FOLDER"
                        echo "Synced: $CHANGED_FILE → $REMOTE_HOST:$REMOTE_FOLDER"
                    '''
                }
            }
        }
    }

    post {
        success { echo "File sync successful: ${params.CHANGED_FILE}" }
        failure  { echo "File sync failed. Check credentials and path." }
    }
}
