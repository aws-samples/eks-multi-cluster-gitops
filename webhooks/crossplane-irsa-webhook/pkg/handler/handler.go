package handler

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"regexp"

	v1 "k8s.io/api/admission/v1"
	admissionregistrationv1 "k8s.io/api/admissionregistration/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/klog"

	iamv1beta1 "github.com/crossplane/provider-aws/apis/iam/v1beta1"
)

func init() {
	_ = corev1.AddToScheme(runtimeScheme)
	_ = admissionregistrationv1.AddToScheme(runtimeScheme)
}

var (
	runtimeScheme    = runtime.NewScheme()
	codecs           = serializer.NewCodecFactory(runtimeScheme)
	deserializer     = codecs.UniversalDeserializer()
	accountIdRegex   = regexp.MustCompile(`\$\{ACCOUNT_ID}|\$ACCOUNT_ID`)
	regionRegex      = regexp.MustCompile(`\$\{AWS_REGION}|\$AWS_REGION`)
	clusterNameRegex = regexp.MustCompile(`\$\{CLUSTER_NAME}|\$CLUSTER_NAME`)
	oidcRegex        = regexp.MustCompile(`\$\{OIDC_PROVIDER}|\$OIDC_PROVIDER`)
)

// ModifierOpt is an option type for setting up a Modifier
type ModifierOpt func(*Modifier)

// WithAccountID sets the AWS account ID
func WithAccountID(a string) ModifierOpt {
	return func(m *Modifier) { m.AccountID = a }
}

// WithRegion sets the AWS Region
func WithRegion(r string) ModifierOpt {
	return func(m *Modifier) { m.Region = r }
}

// WithClusterName sets the EKS cluster name
func WithClusterName(cn string) ModifierOpt {
	return func(m *Modifier) { m.ClusterName = cn }
}

// WithOidcProvider sets the cluster OIDC
func WithOidcProvider(co string) ModifierOpt {
	return func(m *Modifier) { m.OidcProvider = co }
}

// NewModifier returns a Modifier with default values
func NewModifier(opts ...ModifierOpt) *Modifier {
	mod := &Modifier{}

	for _, opt := range opts {
		opt(mod)
	}

	return mod
}

// Modifier holds configuration values for pod modifications
type Modifier struct {
	AccountID    string
	Region       string
	ClusterName  string
	OidcProvider string
}

type patchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

func logContext(roleName, roleGenerateName, namespace string) string {
	name := roleName
	if len(roleName) == 0 {
		name = roleGenerateName
	}
	if len(namespace) == 0 {
		return fmt.Sprintf("Role=%s", name)
	}
	return fmt.Sprintf("Role=%s, "+
		"Namespace=%s",
		name,
		namespace)
}

type Mutator interface {
	Mutate(ar *v1.AdmissionReview, m *Modifier) *v1.AdmissionResponse
}

type RoleMutator struct {
}

// getRoleSpecPatch gets the patch operation to be applied to the given Role
func (rm RoleMutator) getRoleSpecPatch(role *iamv1beta1.Role, m *Modifier) ([]patchOperation, bool) {
	patch := []patchOperation{}

	updatedDoc, changed := m.replacePlaceholders(role.Spec.ForProvider.AssumeRolePolicyDocument)

	if changed {
		assumeRolePolicyDocumentPatch := patchOperation{
			Op:    "replace",
			Path:  "/spec/forProvider/assumeRolePolicyDocument",
			Value: updatedDoc,
		}
		patch = append(patch, assumeRolePolicyDocumentPatch)
	}
	return patch, changed
}

func (rm RoleMutator) Mutate(ar *v1.AdmissionReview, m *Modifier) *v1.AdmissionResponse {
	badRequest := &v1.AdmissionResponse{
		Result: &metav1.Status{
			Message: "bad content",
		},
	}
	if ar == nil {
		return badRequest
	}
	req := ar.Request
	if req == nil {
		return badRequest
	}

	var role iamv1beta1.Role
	if err := json.Unmarshal(req.Object.Raw, &role); err != nil {
		klog.Errorf("Could not unmarshal raw object: %v", err)
		klog.Errorf("Object: %v", string(req.Object.Raw))
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	patch, changed := rm.getRoleSpecPatch(&role, m)

	if changed {
		klog.V(3).Infof("Role was mutated. %s",
			logContext(role.Name, role.GenerateName, role.Namespace))
	} else {
		klog.V(3).Infof("Role was not mutated. Reason: "+
			"Replacement placeholders not found. %s",
			logContext(role.Name, role.GenerateName, role.Namespace))
		return &v1.AdmissionResponse{
			Allowed: true,
		}
	}
	patchBytes, err := json.Marshal(patch)
	if err != nil {
		klog.Errorf("Error marshaling role update: %v", err.Error())
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	return &v1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *v1.PatchType {
			pt := v1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

type PolicyMutator struct {
}

// getPolicySpecPatch gets the patch operation to be applied to the given Policy
func (pm PolicyMutator) getPolicySpecPatch(policy *iamv1beta1.Policy, m *Modifier) ([]patchOperation, bool) {
	patch := []patchOperation{}

	updatedDoc, changed := m.replacePlaceholders(policy.Spec.ForProvider.Document)

	if changed {
		policyDocumentPatch := patchOperation{
			Op:    "replace",
			Path:  "/spec/forProvider/document",
			Value: updatedDoc,
		}
		patch = append(patch, policyDocumentPatch)
	}
	return patch, changed
}

func (pm PolicyMutator) Mutate(ar *v1.AdmissionReview, m *Modifier) *v1.AdmissionResponse {
	badRequest := &v1.AdmissionResponse{
		Result: &metav1.Status{
			Message: "bad content",
		},
	}
	if ar == nil {
		return badRequest
	}
	req := ar.Request
	if req == nil {
		return badRequest
	}

	var policy iamv1beta1.Policy
	if err := json.Unmarshal(req.Object.Raw, &policy); err != nil {
		klog.Errorf("Could not unmarshal raw object: %v", err)
		klog.Errorf("Object: %v", string(req.Object.Raw))
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	patch, changed := pm.getPolicySpecPatch(&policy, m)

	if changed {
		klog.V(3).Infof("Policy was mutated. %s",
			logContext(policy.Name, policy.GenerateName, policy.Namespace))
	} else {
		klog.V(3).Infof("Policy was not mutated. Reason: "+
			"Replacement placeholders not found. %s",
			logContext(policy.Name, policy.GenerateName, policy.Namespace))
		return &v1.AdmissionResponse{
			Allowed: true,
		}
	}
	patchBytes, err := json.Marshal(patch)
	if err != nil {
		klog.Errorf("Error marshaling policy update: %v", err.Error())
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	return &v1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *v1.PatchType {
			pt := v1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

type ServiceAccountMutator struct {
}

// getServiceAccountAnnotationPatch gets the patch operation to be applied to the given ServiceAccount
func (sam ServiceAccountMutator) getServiceAccountAnnotationPatch(sa *corev1.ServiceAccount, m *Modifier) ([]patchOperation, bool) {
	patch := []patchOperation{}
	var updatedDoc string
	changed := false

	annotations := sa.GetAnnotations()
	if irsaAnnotation, ok := annotations["eks.amazonaws.com/role-arn"]; ok {
		updatedDoc, changed = m.replacePlaceholders(irsaAnnotation)
		if changed {
			irsaAnnotationPatch := patchOperation{
				Op:    "replace",
				Path:  "/metadata/annotations/eks.amazonaws.com~1role-arn",
				Value: updatedDoc,
			}
			patch = append(patch, irsaAnnotationPatch)
		}
	}

	return patch, changed
}

func (sam ServiceAccountMutator) Mutate(ar *v1.AdmissionReview, m *Modifier) *v1.AdmissionResponse {
	badRequest := &v1.AdmissionResponse{
		Result: &metav1.Status{
			Message: "bad content",
		},
	}
	if ar == nil {
		return badRequest
	}
	req := ar.Request
	if req == nil {
		return badRequest
	}

	var sa corev1.ServiceAccount
	if err := json.Unmarshal(req.Object.Raw, &sa); err != nil {
		klog.Errorf("Could not unmarshal raw object: %v", err)
		klog.Errorf("Object: %v", string(req.Object.Raw))
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	patch, changed := sam.getServiceAccountAnnotationPatch(&sa, m)

	if changed {
		klog.V(3).Infof("ServiceAccount was mutated. %s",
			logContext(sa.Name, sa.GenerateName, sa.Namespace))
	} else {
		klog.V(3).Infof("ServiceAccount was not mutated. Reason: "+
			"Replacement placeholders not found. %s",
			logContext(sa.Name, sa.GenerateName, sa.Namespace))
		return &v1.AdmissionResponse{
			Allowed: true,
		}
	}
	patchBytes, err := json.Marshal(patch)
	if err != nil {
		klog.Errorf("Error marshaling serviceaccount update: %v", err.Error())
		return &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	return &v1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *v1.PatchType {
			pt := v1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

var Mutators map[string]Mutator = map[string]Mutator{
	"{iam.aws.crossplane.io v1beta1 roles}":    RoleMutator{},
	"{iam.aws.crossplane.io v1beta1 policies}": PolicyMutator{},
	"{ v1 serviceaccounts}":                    ServiceAccountMutator{},
}

func (m *Modifier) Handle(w http.ResponseWriter, r *http.Request) {
	var body []byte
	if r.Body != nil {
		if data, err := ioutil.ReadAll(r.Body); err == nil {
			body = data
		}
	}

	// verify the content type is accurate
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		klog.Errorf("Content-Type=%s, expected application/json", contentType)
		http.Error(w, "Invalid Content-Type, expected `application/json`", http.StatusUnsupportedMediaType)
		return
	}

	var admissionResponse *v1.AdmissionResponse
	ar := v1.AdmissionReview{}
	klog.V(4).Infof("Webhook request payload: %s", string(body))
	if _, _, err := deserializer.Decode(body, nil, &ar); err != nil {
		klog.Errorf("Can't decode body: %v", err)
		admissionResponse = &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else if ar.Request != nil {
		res := fmt.Sprintf("%s", ar.Request.Resource)
		if mutator, ok := Mutators[res]; ok {
			admissionResponse = mutator.Mutate(&ar, m)
		} else {
			admissionResponse = &v1.AdmissionResponse{
				Result: &metav1.Status{
					Message: "Could not identify request resource as any registered target types.",
				},
			}
		}

	} else {
		admissionResponse = &v1.AdmissionResponse{
			Result: &metav1.Status{
				Message: "Could not read request resource.",
			},
		}
	}

	admissionReview := v1.AdmissionReview{
		TypeMeta: metav1.TypeMeta{
			Kind:       "AdmissionReview",
			APIVersion: "admission.k8s.io/v1",
		},
	}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
	}

	resp, err := json.Marshal(admissionReview)
	if err != nil {
		klog.Errorf("Can't encode response: %v", err)
		http.Error(w, fmt.Sprintf("could not encode response: %v", err), http.StatusInternalServerError)
	}
	klog.V(4).Infof("Webhook response payload: %s", string(resp))
	if _, err := w.Write(resp); err != nil {
		klog.Errorf("Can't write response: %v", err)
		http.Error(w, fmt.Sprintf("could not write response: %v", err), http.StatusInternalServerError)
	}
}

func (m Modifier) replacePlaceholders(doc string) (string, bool) {
	docWithRegionReplaced, regionReplaced := m.replaceRegion(doc)
	docWithAccountIDReplaced, accountIDReplaced := m.replaceAccountID(docWithRegionReplaced)
	docWithClusterNameReplaced, clusterNameReplaced := m.replaceClusterName(docWithAccountIDReplaced)
	docWithOIDCReplaced, oidcReplaced := m.replaceOIDC(docWithClusterNameReplaced)

	return docWithOIDCReplaced, (regionReplaced || accountIDReplaced || clusterNameReplaced || oidcReplaced)
}

func (m Modifier) replaceAccountID(str string) (string, bool) {
	loc := accountIdRegex.FindStringIndex(str)
	changed := false
	if loc == nil {
		return str, changed
	}
	changed = true
	return accountIdRegex.ReplaceAllString(str, m.AccountID), changed
}

func (m Modifier) replaceRegion(str string) (string, bool) {
	loc := regionRegex.FindStringIndex(str)
	changed := false
	if loc == nil {
		return str, changed
	}
	changed = true
	return regionRegex.ReplaceAllString(str, m.Region), changed
}

func (m Modifier) replaceClusterName(str string) (string, bool) {
	loc := clusterNameRegex.FindStringIndex(str)
	changed := false
	if loc == nil {
		return str, changed
	}
	changed = true
	return clusterNameRegex.ReplaceAllString(str, m.ClusterName), changed
}

func (m Modifier) replaceOIDC(str string) (string, bool) {
	loc := oidcRegex.FindStringIndex(str)
	changed := false
	if loc == nil {
		return str, changed
	}
	changed = true
	return oidcRegex.ReplaceAllString(str, m.OidcProvider), changed
}
