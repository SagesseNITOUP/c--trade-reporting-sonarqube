import jenkins.model.Jenkins
import hudson.util.Secret
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def instance = Jenkins.get()
def sonarToken = new File('/run/secrets/jenkins_sonar_token').getText('UTF-8').trim()
if (!sonarToken) {
    throw new IllegalStateException('Secret SonarQube manquant. Lancer scripts/jenkins.ps1 start.')
}
def provider = SystemCredentialsProvider.getInstance()
if (!provider.getCredentials().any { it.id == 'sonar-token' }) {
    provider.getCredentials().add(new StringCredentialsImpl(
        CredentialsScope.GLOBAL, 'sonar-token',
        'Analyse du projet trade-reporting-boost-demo', Secret.fromString(sonarToken)
    ))
    provider.save()
}

def jobName = 'trade-reporting-coverage'
def job = instance.getItem(jobName)
if (job == null) {
    job = instance.createProject(WorkflowJob, jobName)
    job.setDescription('Demonstration locale : Boost.Test, gcovr, SonarQube et Quality Gate. Sources depuis /opt/project.')
    job.setDefinition(new CpsFlowDefinition(new File('/opt/project/Jenkinsfile').getText('UTF-8'), true))
    job.save()
}
instance.save()
println('Jenkins local configure : identifiant SonarQube et job de couverture disponibles.')
