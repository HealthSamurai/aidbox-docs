---
description: Understand Aidbox storage format differences from FHIR including parsed references and union types.
---

# Aidbox and FHIR formats

Aidbox stores FHIR resources almost as is with 2 types of isomorphic transformations:

* References
* Union (Choice Types)

### References:

In FHIR, references are represented as URI string. In most cases, you are interested in discrete parts of references like resource id and type. For performance and accuracy reasons Aidbox parses reference and stores its parts in discrete fields. There are three types of references - absolute, relative, and local. Aidbox parses them into different attributes.

**Relative** (interpreted as a reference to a resource on the same server; trigger referential consistency check) :

```yaml
# FHIR
subject:
  reference: "Patient/pt-1" 

# Aidbox
subject:
  resourceType: "Patient"
  id: "pt-1"
```

**reference** is parsed into a pair of **`{id,resourceType}`** attributes

**Absolute** (interpreted as a reference to an external resource;  no ref validation)

```yaml
# FHIR
subject:
  reference: "http://external/fhir/Patient/pt-1" 

# Aidbox
subject:
  uri: "http://external/fhir/Patient/pt-1"
```

reference is parsed into the **uri** attribute

**Local** (interpreted as a local ref to contained resources )

```yaml
# FHIR
subject:
  reference: "#pt" 

# Aidbox
subject:
  localRef: "pt"
```

reference is parsed into a **ref** attribute

### Union (Choice) Types:

Some elements can have multiple types. Such elements in FHIR spec prefixed with `[x]` like `Observation.value[x]` and represented in JSON in a _wrong_ (postfixed) way like`Observation.valueString` . The simple logical check "why it's wrong" is "you could not have a collection of union elements in FHIR JSON!". Aidbox fixes this moving type as a key inside a nested object - `valueString:... => value: {string: ...}`

```yaml
#FHIR
resourceType: Observation
valueQuantity:
  unit: ...
  value: ...

# becomes Aidbox
resourceType: Observation
value:
  Quantity:
    unit: ...
    value: ...
```
