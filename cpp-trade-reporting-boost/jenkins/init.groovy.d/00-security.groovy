import jenkins.model.Jenkins
import jenkins.install.InstallState
import hudson.model.User
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

// Classes du coeur seulement : la securite ne depend pas du chargement des plugins.
def instance = Jenkins.get()
def realm = instance.getSecurityRealm()
if (!(realm instanceof HudsonPrivateSecurityRealm) || realm.allowsSignup()) {
    realm = new HudsonPrivateSecurityRealm(false, false, null)
    instance.setSecurityRealm(realm)
}
def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(authorization)
// Fermer l'acces anonyme avant toute lecture ou validation d'un secret.
instance.save()

def password = new File('/run/secrets/jenkins_admin_password').getText('UTF-8').trim()
if (!password) {
    throw new IllegalStateException('Secret administrateur Jenkins manquant. Lancer scripts/jenkins.ps1 start.')
}
if (User.getById('admin', false) == null) {
    realm.createAccount('admin', password)
}
instance.setNumExecutors(1)
instance.setLabelString('linux-coverage')
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
instance.save()
println('Authentification Jenkins locale configuree ; acces anonyme ferme.')
