<!-- job=paper-v6 backend=mlx seconds=188 calls=8 prompt_tokens=9368 gen_tokens=3073 source_chars=10185 source_tokens=2422 note_chars=9824 metrics={'chars': 9824, 'copy_ratio': 0.198, 'fillers': 2, 'dup_headings': 0, 'sections': 5, 'callouts': 13} -->
# The Power of Attention: How Transformers Look Backwards for Answers
Imagine you're searching for answers in a dictionary, comparing your query with every key to produce similarity scores that sum up to one. This is exactly what the attention mechanism does in Transformer models, allowing them to weigh token relationships and decide which input positions are relevant for each output step.

> [!summary] Overview
> The attention mechanism was introduced as an add-on to recurrent encoder-decoder models in 2015 but became a key component of the Transformer model in 2017. It enables the decoder to look back at every encoder state and decide which input positions are relevant for each output step. By representing tokens with vectors and computing query-key pairs, transformers can compute similarity scores that determine weights summing up to one. Multi-head attention is used to parallelize this process, reducing the total cost of computation while maintaining model capacity. Self-attention computes weighted averages based on similarities between query-key pairs, allowing transformers to capture complex patterns in data. The magic of multi-head attention lies in its ability to scale down weights, making it easier to choose between similar inputs, while cross-attention enables models to decode based on information from the entire input sequence. By applying a causal mask and zeroing out padding tokens, transformers can prevent language models from looking at future context.

## The Power of Attention: How Transformers Look Backwards

In 2015, Bahdanau et al. introduced the attention mechanism as an add-on to recurrent encoder-decoder models. Later, in 2017, it became a key component of the Transformer model.

The main purpose of attention is to allow the decoder to look back at every encoder state and decide which input positions are relevant for each output step. ==This process is like searching for answers in a dictionary==, where the query is compared with every key, producing similarity scores that are turned into weights that sum to one.

### Representing Tokens as Vectors

In the Transformer model, each token in the input is represented by a vector x_i of dimension d_model. Three learned linear maps produce:

- Query q_i = x_i W^Q
- Key k_i = x_i W^K
- Value v_i = x_i W^V

These vectors represent the query, key, and value for each token.

### The Attention Operation

The attention operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V, where Q, K, and V are matrices representing the query, key, and value vectors.

> [!tip] Don't forget about the dot product
> The dot product of Q and K measures how strongly token i attends to token j.

### Normalizing Scores

Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing gradients from shrinking or exploding.

| Token | Raw scores against keys |
|---|---|
| 1   | (8, 4, 0)             |
| 2   | (6, 3, 1)             |
| 3   | (9, 5, 2)             |

> [!example] Finding relevant tokens
> For the first token with d_k = 4, the raw scores are (8, 4, 0).

## The Magic of Multi-Head Attention in Transformers

### Scaling Down the Weights
When scaling down the weights, we get approximately **(0.87, 0.12, 0.02)**, with the output for token 1 being mostly its own value. This is because the scaling factor of 0.5 reduces the importance of the other tokens.

Without scaling, the weights would be about **(0.98, 0.02, 0.00)**, making it a "harder" choice. The smaller values make it more difficult to choose between similar inputs.

### Self-Attention: Gathering Information
**Self-attention** occurs when Q, K, and V are computed from the same sequence. Every token builds a new representation by gathering information from other tokens in the same sentence.

> [!example] A single attention mechanism can learn many things
> Empirical results show that different heads learn to specialize: some track previous tokens, others link pronouns to nouns, and others follow syntactic relations.

### Cross-Attention: Decoding with Encoder Output
**Cross-attention** is used in decoder models, where queries come from the decoder while keys and values come from the encoder output. This allows the model to decode based on information from the entire input sequence.

### Masking Out Future Tokens
To prevent language models from looking at future tokens, a **causal mask** is applied before softmax, setting scores (i, j) with j > i to minus infinity.

> [!tip] Preventing future tokens from influencing current ones
> Masking helps ensure that each token's representation is independent of its future context.

### Ignoring Padding Tokens
The same mechanism used for masking out future tokens is also used to set weights to zero for padding tokens.

### Multi-Head Attention: Parallelizing Self-Attention
**Multi-head attention** runs h attention operations in parallel, each with its own projection matrices, producing one weighted average per token. This approach reduces the total cost of multi-head attention compared to a single full-width head.

> [!warning] Be aware of the trade-off between accuracy and computational resources
> The smaller sub-space dimensions can lead to faster computations but may also reduce model capacity.

### Positional Information: Permutation-Invariant Attention
**Positional information** is permutation-invariant, meaning the model has no idea of word order unless supplied with positional encoding vectors.

> [!example] Without positional information, models struggle to maintain context
> Empirical results show that many later models instead learn position embeddings directly or use relative schemes like rotary position embeddings (RoPE).

### Combining Self-Attention and Feed-Forward Networks
A Transformer layer combines two sub-layers: **multi-head self-attention** and a **position-wise feed-forward network (FFN)** applied independently to every token.

| Layer | Multi-Head Attention | Position-Wise FFN |
|---|---|---|
| 1    | Yes                    | Yes              |
| 2    | Yes                    | Yes              |

> [!tip] Understanding the components of a Transformer layer
> Each sub-layer is crucial for the overall performance of the model.

## **Self-Attention**: How Transformers Weigh Token Relationships

**Self-attention** is a key component of Transformers that computes a weighted average of value vectors based on similarities between query-key pairs. ==Weights are determined by a softmax over these similarities==.

### Multiple Heads: Simultaneous Attention
By using multiple heads, the model can attend to several relationships simultaneously. This allows it to capture complex patterns in the data.

### Block Structure: Attention + FFN
Each block consists of attention and feed-forward neural network (FFN) layers, with residual connections and layer normalization used for stability and efficiency.

> [!warning] Computational Cost
> The cost of full self-attention is quadratic in sequence length, which can be a significant challenge for long sequences.

### **Key Points**:
- **Self-Attention**: Each token's weight is determined by its similarity to every other token.
- **Similarity Scores**: The largest weights are typically found for tokens that are most similar to themselves (i.e. identical tokens).

### Exercise: Repeating the Example
Repeat the worked example of Section 9.3 with scores (6, 6, 0) and d_k = 9.

### **Exercise**
- [ ] Repeat the calculation to find the weights for each token.

The tokens receiving the largest weights will be the ones with the highest similarity scores, which in this case are likely to be the first token (6, 6).

## Key takeaways
- The attention mechanism allows the decoder to look back at every encoder state and decide which input positions are relevant for each output step by computing a weighted average of value vectors with weights given by a softmax over query-key similarities.
- Attention is permutation-invariant, meaning the model has no idea of word order unless supplied with positional encoding vectors.
- Multi-head attention runs h attention operations in parallel, each with its own projection matrices, producing one weighted average per token and allowing the model to attend to several relationships at once.
- The Transformer layer combines two sub-layers: multi-head self-attention and a position-wise feed-forward network (FFN) applied independently to every token.
- Self-attention computes a weighted average of value vectors, with weights given by a softmax over query-key similarities.

## Review questions

> [!question] What is the main purpose of attention in recurrent encoder-decoder models?
> **Answer:** The main purpose of attention is to allow the decoder to look back at every encoder state and decide which input positions are relevant for each output step.

> [!question] How does the dot product of Q and K measure how strongly token i attends to token j?
> **Answer:** The dot product of Q and K measures how strongly token i attends to token j, as it represents the similarity between the two tokens.

> [!question] What is the difference between self-attention and cross-attention in the Transformer model?
> **Answer:** Self-attention occurs when Q, K, and V are computed from the same sequence, allowing every token to build a new representation by gathering information from other tokens. Cross-attention is used in decoder models, where queries come from the decoder while keys and values come from the encoder output.

> [!question] Why is it necessary to apply a causal mask before softmax in language models?
> **Answer:** A causal mask is applied to prevent language models from looking at future tokens, ensuring that the model only attends to past tokens and ignores future ones.
