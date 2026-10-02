<!-- job=paper-v4 backend=mlx seconds=184 calls=8 prompt_tokens=9270 gen_tokens=2930 source_chars=10185 source_tokens=2422 note_chars=8911 metrics={'chars': 8911, 'copy_ratio': 0.205, 'fillers': 1, 'dup_headings': 0, 'sections': 6, 'callouts': 15} -->
# Soft Dictionary Lookup: How Attention Works in Transformers
The attention mechanism is so powerful that it can even cool down the entire planet by about 0.5 °C for almost two years. Yet, most people don't know how this works, let alone why some volcanoes ooze while others explode violently.

> [!summary] Overview
> The attention mechanism was introduced to address weaknesses of sequential computation and information retention. In transformers, attention relaxes traditional dictionary queries where either matches or does not return a value; instead, every value contributes in proportion to how well its key matches the query. Attention is used in multi-head attention, self-attention, and other components of transformer models, allowing them to focus on the right things and capture complex patterns in data.

## Soft Dictionary Lookup: How Attention Works in Transformers

The attention mechanism was introduced as an add-on to recurrent encoder-decoder models (**Bahdanau et al., 2015**) to address weaknesses of sequential computation and information retention.

### Why Use Attention?
The main reason for using attention is to allow the decoder to look back at every encoder state and decide which input positions are relevant for each output step.

> [!definition] **Attention as a soft dictionary lookup**
It relaxes the traditional dictionary query where either matches or does not, returning the corresponding value; instead, every value contributes in proportion to how well its key matches the query.

### Representing Tokens
Each token in the input is represented by a vector x_i of dimension d_model. Three learned linear maps produce:

| Component | Formula |
| --- | --- |
| Query q_i = x_i W^Q | q_i = x_i * W^Q |
| Key k_i = x_i W^K | k_i = x_i * W^K |
| Value v_i = x_i W^V | v_i = x_i * W^V |

### The Complete Attention Operation
The complete attention operation is written as: **Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V**

> [!tip] Scaled dot-product attention
The Transformer uses the dot product as its similarity function; the product Q K^T measures how strongly token i attends to token j.

### How Softmax Works
The softmax is applied row by row, so each row becomes a probability distribution over the n positions. Multiplying by V then mixes the value vectors according to those probabilities.

| Token | Raw Scores Against Keys | Probability Distribution |
| --- | --- | --- |
| 1    | (8, 4, 0)               | [0.25, 0.5, 0.25]        |
| 2    | (6, 3, 1)                | [0.33, 0.34, 0.33]        |
| 3    | (9, 5, 2)                | [0.58, 0.21, 0.21]        |

> [!warning] Preventing learning stalls
Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing learning stalls due to saturated scores.

- [ ] Try working through more examples

## Multi-Head Attention: How Transformers Focus on the Right Things

### **Parallel Processing**
In multi-head attention, h attention operations are run **in parallel**, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace.

> [!definition] **MultiHead(Q, K, V)**
> Outputs of h attention operations concatenated and passed through a final linear map W^O to produce MultiHead(Q, K, V).

### **Interpreting Attention Heads**
Empirical results show that different heads learn to specialize: some track previous tokens, others link pronouns to nouns they refer to, and others follow syntactic relations. However, these interpretations should be treated with caution; heads are not guaranteed to have a clean meaning.

- [ ] Be cautious when interpreting attention head meanings

### **Permutation-Invariance**
Attention is permutation-invariant, meaning that shuffling the input tokens shuffles the output in the same way but otherwise unchanged.

> [!tip] Don't worry about shuffling input tokens
> Attention remains unchanged under token permutations.

### **Positional Information**
To address this limitation, positional encoding vectors are added to each input embedding. These vectors are built from sine and cosine functions of different frequencies.

| Dimension | Sine/Cosine Frequency |
|---|---|
| 1 | High frequency |
| 2 | Medium frequency |
| 3 | Low frequency |

### **Transformer Layer Structure**
A Transformer layer combines two sub-layers: multi-head self-attention and a position-wise feed-forward network (FFN) applied independently to every token.

> [!definition] **FFN**
> Defined as:
> - ReLU activation function
> - Linear transformation

### **Repeating the Block**
This block is repeated multiple times in a transformer model, allowing it to process sequences of tokens.

## Self-Attention: How it Works and its Computational Cost

### Weights and Averages
Self-attention computes a weighted average of value vectors based on similarities between **query** and **key** vectors. ==Softmax is used to normalize these weights==, ensuring that the output is a probability distribution.

> [!definition] Softmax
> Softmax: function that takes in a vector and returns a probability distribution over all possible values.

### Scaling for Stability
To prevent the softmax from saturating, **scaling is done by sqrt(d_k)**. This helps ensure that the weights are properly normalized and that the model can learn meaningful relationships between query-key pairs.

- [ ] Understand the importance of scaling

### Multiple Heads for Multi-Relationships
Using multiple **heads** allows the model to attend to several relationships at once. This increases the capacity of the model and enables it to capture complex patterns in data.

> [!tip] More heads = more relationships = better performance

### Positional Encodings
**Positional encodings** are used to restore word-order information. Without these, the model would not be able to distinguish between sentences like "dog bites man" and "man bites dog".

> [!warning] No positional encodings = no word order
> Model cannot distinguish between "dog bites man" and "man bites dog"

### Block Structure
Each block consists of **attention + FFN**, with residual connections and LayerNorm: output = LayerNorm(x + Sublayer(x)).

- [ ] Understand the role of residual connections

### Computational Cost
The cost of full self-attention is **quadratic in sequence length**: O(n^2 d) for a sequence of length n. This means that as the input sequence gets longer, the computational cost increases exponentially.

> [!tip] Be aware of the computational cost
> Full self-attention can be computationally expensive

## Example: Determining Token Weights

Given scores (6, 6, 0) and d_k = 9, we need to determine which tokens receive the largest weights.

| Query | Key | Score |
|---|---|---|
| 6   | 6   | 6    |
| 6   | 0   | 0    |

The token with score 6 receives the largest weight because it has the highest similarity between its query and key vectors.

## Key takeaways
- The attention mechanism allows the decoder to look back at every encoder state and decide which input positions are relevant for each output step.
- Scaled dot-product attention is used in the Transformer, where the product Q K^T measures how strongly token i attends to token j.
- Multi-head attention allows the model to attend to several relationships at once by running h attention operations in parallel.
- Positional encodings are used to restore word-order information and prevent the softmax from saturating.

## Review questions

> [!question] Why does the Transformer use scaled dot-product attention instead of a traditional dictionary query?
> **Answer:** The Transformer uses scaled dot-product attention because it relaxes the traditional dictionary query where either matches or does not, returning the corresponding value; instead, every value contributes in proportion to how well its key matches the query.

> [!question] How do positional encoding vectors help address the limitation of permutation-invariant attention?
> **Answer:** Positional encoding vectors help address the limitation of permutation-invariant attention by adding distinct patterns to each input embedding, allowing the model to distinguish between different word orders.

> [!question] What is the main difference between multi-head attention and single-head attention?
> **Answer:** The main difference between multi-head attention and single-head attention is that multi-head attention allows the model to attend to several relationships at once by running h attention operations in parallel, whereas single-head attention uses a single attention operation.

> [!question] Why does the Transformer use a position-wise feed-forward network (FFN) instead of a traditional FFNN?
> **Answer:** The Transformer uses a position-wise feed-forward network (FFN) because it applies the FNN independently to every token, allowing the model to process each token separately and maintain its word order information.
