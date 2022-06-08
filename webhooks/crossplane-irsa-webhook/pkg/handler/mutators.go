package handler

import (
	"encoding/json"

	iamv1beta1 "github.com/crossplane/provider-aws/apis/iam/v1beta1"
	v1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/klog"
)

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
