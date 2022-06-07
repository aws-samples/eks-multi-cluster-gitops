package handler

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"

	v1 "k8s.io/api/admission/v1"
	authenticationv1 "k8s.io/api/authentication/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
)

func TestMutators(t *testing.T) {
	modifier := NewModifier()
	cases := []struct {
		caseName string
		input    *v1.AdmissionReview
		response *v1.AdmissionResponse
	}{
		{
			"nilBody",
			nil,
			&v1.AdmissionResponse{Result: &metav1.Status{Message: "bad content"}},
		},
		{
			"NoRequest",
			&v1.AdmissionReview{Request: nil},
			&v1.AdmissionResponse{Result: &metav1.Status{Message: "bad content"}},
		},
	}

	for k, mutator := range Mutators {
		for _, c := range cases {
			t.Run(c.caseName+k, func(t *testing.T) {
				response := mutator.Mutate(c.input, modifier)

				if !reflect.DeepEqual(response, c.response) {
					got, _ := json.MarshalIndent(response, "", "  ")
					want, _ := json.MarshalIndent(c.response, "", "  ")
					t.Errorf("Unexpected response. Got \n%s\n wanted \n%s", string(got), string(want))
				}
			})
		}
	}
}

var jsonPatchType = v1.PatchType("JSONPatch")

var rawRoleWithPlaceholders = []byte(`
{
	"apiVersion": "iam.aws.crossplane.io/v1beta1",
	"kind": "Role",
	"metadata": {
		"name": "sample-irsa-role",
		"labels": {
			"type": "sample-irsa-role"
		}
	},
	"spec": {
		"forProvider": {
			"assumeRolePolicyDocument": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"${OIDC_PROVIDER}:aud\":\"sts.amazonaws.com\",\"${OIDC_PROVIDER}:sub\":\"system:serviceaccount:my-namespace:my-service-account\"}}}]}"
		},
		"providerConfigRef": {
			"name": "default"
		}
	}
}
`)

var rawServiceAccountWithPlaceholders = []byte(`
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "annotations": {
      "eks.amazonaws.com/role-arn": "arn:aws:iam::${ACCOUNT_ID}:role/my-sample-irsa-role"
    },
    "name": "my-sample-irsa-sa",
    "namespace": "crossplane-system"
  }
}
`)

var rawPolicyWithPlaceholders = []byte(`
{
  "apiVersion": "iam.aws.crossplane.io/v1beta1",
  "kind": "Policy",
  "metadata": {
    "name": "crossplane-irsa-webhook-policy"
  },
  "spec": {
    "forProvider": {
      "name": "crossplane-irsa-webhook-policy",
      "document": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"eks:DescribeCluster\",],\"Resource\":[\"arn:aws:eks:${AWS_REGION}:${ACCOUNT_ID}:cluster/${CLUSTER_NAME}\"]}]}"
    },
    "providerConfigRef": {
      "name": "default"
    }
  }
}
`)

const AWS_REGION string = "eu-west-1"
const ACCOUNT_ID string = "123456789012"
const CLUSTER_NAME string = "staging"
const CLUSTER_OIDC string = "oidc.eks.eu-west-1.amazonaws.com/id/6A0A07D566C756AECD797B338FAA4A4D"

var rolePatch = []byte(
	fmt.Sprintf(
		`[{"op":"replace","path":"/spec/forProvider/assumeRolePolicyDocument","value":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::%[1]s:oidc-provider/%[2]s\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"%[2]s:aud\":\"sts.amazonaws.com\",\"%[2]s:sub\":\"system:serviceaccount:my-namespace:my-service-account\"}}}]}"}]`,
		ACCOUNT_ID,
		CLUSTER_OIDC,
	),
)

var serviceAccountPatch = []byte(
	fmt.Sprintf(
		`[{"op":"replace","path":"/metadata/annotations/eks.amazonaws.com~1role-arn","value":"arn:aws:iam::%[1]s:role/my-sample-irsa-role"}]`,
		ACCOUNT_ID,
	),
)

var policyPatch = []byte(
	fmt.Sprintf(
		`[{"op":"replace","path":"/spec/forProvider/document","value":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"eks:DescribeCluster\",],\"Resource\":[\"arn:aws:eks:%[2]s:%[1]s:cluster/%[3]s\"]}]}"}]`,
		ACCOUNT_ID,
		AWS_REGION,
		CLUSTER_NAME,
	),
)

const REQUEST_UID string = "918ef1dc-928f-4525-99ef-988389f263c3"

var rawRoleWithoutPlaceholders = []byte(`
{
	"apiVersion": "iam.aws.crossplane.io/v1beta1",
	"kind": "Role",
	"metadata": {
		"name": "eks-cluster-role",
		"labels": {
			"type": "eks-cluster-role"
		}
	},
	"spec": {
		"forProvider": {
			"assumeRolePolicyDocument": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"eks.amazonaws.com\"},\"Action\":\"sts:AssumeRole\"}]}"
		},
		"providerConfigRef": {
			"name": "default"
		}
	}
}
`)

var rawServiceAccountWithoutPlaceholders = []byte(`
{
  "apiVersion": "v1",
  "kind": "ServiceAccount",
  "metadata": {
    "name": "my-simple-sa"
  }
}
`)

var rawPolicyWithoutPlaceholders = []byte(`
{
  "apiVersion": "iam.aws.crossplane.io/v1beta1",
  "kind": "Policy",
  "metadata": {
    "name": "secrets-manager-policy"
  },
  "spec": {
    "forProvider": {
      "name": "secrets-manager-policy",
      "document": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"secretsmanager:GetResourcePolicy\",\"secretsmanager:GetSecretValue\",\"secretsmanager:DescribeSecret\",\"secretsmanager:ListSecretVersionIds\"],\"Resource\":[\"arn:aws:secretsmanager:*:*:secret:sealed-secrets*\"]}]}"
    },
    "providerConfigRef": {
      "name": "default"
    }
  }
}
`)

var validResponseNoPatch = &v1.AdmissionResponse{
	UID:     types.UID(REQUEST_UID),
	Allowed: true,
}

func getValidReview(gvr *metav1.GroupVersionResource, gvk *metav1.GroupVersionKind, raw []byte) *v1.AdmissionReview {
	return &v1.AdmissionReview{
		Request: &v1.AdmissionRequest{
			UID:       types.UID(REQUEST_UID),
			Resource:  *gvr,
			Kind:      *gvk,
			Operation: "CREATE",
			UserInfo: authenticationv1.UserInfo{
				Username: "kubernetes-admin",
				UID:      "aws-iam-authenticator:111122223333:AROAR2TG44V5CLZCFPOQZ",
				Groups:   []string{"system:authenticated", "system:masters"},
			},
			Object: runtime.RawExtension{
				Raw: raw,
			},
			DryRun: nil,
		},
		Response: nil,
	}
}

func serializeAdmissionReview(t *testing.T, ar *v1.AdmissionReview) []byte {
	wantedBytes, err := json.Marshal(ar)
	if err != nil {
		t.Errorf("Failed to marshal desired response: %v", err)
		return nil
	}
	return wantedBytes
}

func getValidResponseWithPatch(validPatch []byte) *v1.AdmissionResponse {
	return &v1.AdmissionResponse{
		UID:       types.UID(REQUEST_UID),
		Allowed:   true,
		Patch:     validPatch,
		PatchType: &jsonPatchType,
	}
}

func TestModifierHandler(t *testing.T) {
	modifier := NewModifier(
		WithAccountID(ACCOUNT_ID),
		WithRegion(AWS_REGION),
		WithClusterName(CLUSTER_NAME),
		WithOidcProvider(CLUSTER_OIDC),
	)

	ts := httptest.NewServer(
		http.HandlerFunc(modifier.Handle),
	)
	defer ts.Close()

	cases := []struct {
		caseName         string
		input            []byte
		inputContentType string
		want             []byte
	}{
		{
			"nilBody",
			nil,
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: &v1.AdmissionResponse{Result: &metav1.Status{Message: "Could not read request resource."}},
			}),
		},
		{
			"NoRequest",
			serializeAdmissionReview(t, &v1.AdmissionReview{Request: nil}),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: &v1.AdmissionResponse{Result: &metav1.Status{Message: "Could not read request resource."}},
			}),
		},
		{
			"BadContentType",
			serializeAdmissionReview(t, &v1.AdmissionReview{Request: nil}),
			"application/xml",
			[]byte("Invalid Content-Type, expected `application/json`\n"),
		},
		{
			"InvalidJSON",
			[]byte(`{"request": {"object": "\"metadata\":{\"name\":\"fake\""}`),
			"application/json",
			[]byte(`{"kind":"AdmissionReview","apiVersion":"admission.k8s.io/v1","response":{"uid":"","allowed":false,"status":{"metadata":{},"message":"couldn't get version/kind; json parse error: unexpected end of JSON input"}}}`),
		},
		{
			"InvalidRoleBytes",
			[]byte(`{"request": {"object": "\"metadata\":{\"name\":\"fake\""}}`),
			"application/json",
			[]byte(`{"kind":"AdmissionReview","apiVersion":"admission.k8s.io/v1","response":{"uid":"","allowed":false,"status":{"metadata":{},"message":"Could not identify request resource as any registered target types."}}}`),
		},
		{
			"ValidRoleNoPatch",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "iam.aws.crossplane.io",
						Version:  "v1beta1",
						Resource: "roles",
					},
					&metav1.GroupVersionKind{
						Group:   "iam.aws.crossplane.io",
						Version: "v1beta1",
						Kind:    "Role",
					},
					rawRoleWithoutPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: validResponseNoPatch,
			}),
		},
		{
			"ValidRolePatched",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "iam.aws.crossplane.io",
						Version:  "v1beta1",
						Resource: "roles",
					},
					&metav1.GroupVersionKind{
						Group:   "iam.aws.crossplane.io",
						Version: "v1beta1",
						Kind:    "Role",
					},
					rawRoleWithPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: getValidResponseWithPatch(rolePatch),
			}),
		},
		{
			"ValidServiceAccountNoPatch",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "",
						Version:  "v1",
						Resource: "serviceaccounts",
					},
					&metav1.GroupVersionKind{
						Group:   "",
						Version: "v1",
						Kind:    "ServiceAccount",
					},
					rawServiceAccountWithoutPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: validResponseNoPatch,
			}),
		},
		{
			"ValidServiceAccountPatched",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "",
						Version:  "v1",
						Resource: "serviceaccounts",
					},
					&metav1.GroupVersionKind{
						Group:   "",
						Kind:    "ServiceAccount",
						Version: "v1",
					},
					rawServiceAccountWithPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: getValidResponseWithPatch(serviceAccountPatch),
			}),
		},
		{
			"ValidPolicyNoPatch",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "iam.aws.crossplane.io",
						Version:  "v1beta1",
						Resource: "policies",
					},
					&metav1.GroupVersionKind{
						Group:   "iam.aws.crossplane.io",
						Version: "v1beta1",
						Kind:    "Policy",
					},
					rawPolicyWithoutPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: validResponseNoPatch,
			}),
		},
		{
			"ValidPolicyPatched",
			serializeAdmissionReview(
				t,
				getValidReview(
					&metav1.GroupVersionResource{
						Group:    "iam.aws.crossplane.io",
						Version:  "v1beta1",
						Resource: "policies",
					},
					&metav1.GroupVersionKind{
						Group:   "iam.aws.crossplane.io",
						Kind:    "Policy",
						Version: "v1beta1",
					},
					rawPolicyWithPlaceholders,
				),
			),
			"application/json",
			serializeAdmissionReview(t, &v1.AdmissionReview{
				TypeMeta: metav1.TypeMeta{
					Kind:       "AdmissionReview",
					APIVersion: "admission.k8s.io/v1",
				},
				Response: getValidResponseWithPatch(policyPatch),
			}),
		},
	}

	for _, c := range cases {
		t.Run(c.caseName, func(t *testing.T) {
			var buf io.Reader
			if c.input != nil {
				buf = bytes.NewBuffer(c.input)
			}
			client := &http.Client{}
			req, err := http.NewRequest("POST", ts.URL, buf)
			if err != nil {
				t.Errorf("Failed to create new request: %v", err)
				return
			}
			req.Close = true

			req.Header.Set("Content-Type", c.inputContentType)
			resp, err := client.Do(req)

			if err != nil {
				t.Errorf("Failed to make request: %v", err)
				return
			}
			responseBytes, err := ioutil.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil {
				t.Errorf("Failed to read response: %v", err)
				return
			}

			if !bytes.Equal(responseBytes, c.want) {
				t.Errorf("Expected response didn't match: \nGot\n\t\"%v\"\nWanted:\n\t\"%v\"\n",
					string(responseBytes),
					string(c.want),
				)
			}
		})
	}
}
