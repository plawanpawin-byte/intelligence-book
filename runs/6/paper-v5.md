<!-- job=paper-v5 backend=mlx seconds=150 calls=8 prompt_tokens=9707 gen_tokens=2940 source_chars=10185 source_tokens=2422 note_chars=8567 metrics={'chars': 8567, 'copy_ratio': 0.195, 'fillers': 1, 'dup_headings': 0, 'sections': 8, 'callouts': 13} -->
# The Power of Attention in Transformers: How Self-Attention Outshines RNNs

Did you know that before 2017, most models for sequence tasks relied on recurrent neural networks (RNNs)? These models had two significant weaknesses: computation was inherently sequential, making training non-parallelizable, and information about early tokens must survive many repeated applications of the model to influence late predictions.

> [!summary] Overview
> In this note, we'll explore how the Transformer model overcomes these limitations by introducing the attention mechanism. Specifically, we'll delve into three key components: Multi-Head Attention, Self-Attention, and Positional Encodings. By understanding how these mechanisms work together, you'll gain insight into why Transformers have revolutionized sequence processing in NLP tasks.

## The Power of Attention: How Transformers Outshine RNNs

Before 2017, most models for sequence tasks relied on **recurrent neural networks (RNNs)**, which had two significant weaknesses:

### Weaknesses of RNNs
- Computation is inherently sequential, making training non-parallelizable.
- Information about early tokens must survive many repeated applications of the model to influence late predictions.

The attention mechanism was introduced as an add-on to recurrent encoder-decoder models and later developed into the Transformer, removing recurrence entirely. This marked a significant shift towards more efficient and effective sequence processing.

## The Magic of Attention
Attention can be thought of as a **soft dictionary lookup**: comparing a query with every key produces similarity scores, which are turned into weights that sum to one, and the output is the weighted average of all values.

### How it Works
Each token in the input is represented by a vector x_i of dimension d_model, produced by three learned linear maps:

- Query q_i = x_i W^Q
- Key k_i = x_i W^K
- Value v_i = x_i W^V

The complete attention operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V (9.1)

## The Dot Product: A Measure of Relevance
The dot product is used as the similarity function, resulting in an n x n matrix whose entry (i, j) measures how strongly token i attends to token j.

### Normalizing Scores for Better Results
Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing gradients from becoming too small or exploding.

| Token | Raw Score Against Keys |
|---|---|
| 1   | (8, 4, 0)          |

- [ ] Practice attention mechanism with worked examples

## Multi-Head Attention: how it works and its components

Multi-head attention is a key component of the Transformer model. It's essentially a way for the model to weigh the importance of different input tokens when generating an output.

### Scaled Weights
The weights are scaled by 1/sqrt(4) = 0.5, resulting in approximately (0.87, 0.12, 0.02), with the output for token 1 being mostly its own value. Without scaling, the weights would be about (0.98, 0.02, 0.00).

> [!tip] Scaling is crucial to avoid over-attention
> Scaled weights help prevent tokens from dominating the attention mechanism.

### Self-Attention and Cross-Attention
Self-attention occurs when Q, K, and V are computed from the same sequence, where every token builds a new representation by gathering information from other tokens in the same sentence. Cross-attention is used in encoder-decoder models, where queries come from the decoder while keys and values come from the encoder output.

> [!example] A simple example of self-attention
> Every token gathers information from other tokens in the same sentence to build its representation.

### Masking and Multi-Head Attention
Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace. The outputs are concatenated and passed through a final linear map W^O: MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O.

| Head | Q | K | V |
|---|---|---|---|
| 1   | 0.87 | 0.12 | 0.02 |
| 2   | 0.98 | 0.02 | 0.00 |

### Specialized Heads
Each head works with d_k = d_v = 64 dimensions; empirically, different heads learn to specialize in tracking previous tokens, pronouns, or syntactic relations.

> [!tip] Different heads can learn specialized representations
> This helps the model track specific information and improve its performance.

- [ ] Understand how attention mechanisms work

## The Magic of Self-Attention in Transformers

### Weighing Attention: How Self-Attention Works
Self-attention is a mechanism that computes a weighted average of value vectors based on similarities between query-key pairs. ==This process relies on a softmax function to normalize the weights, ensuring that the output is a probability distribution==.

To prevent the softmax from saturating, it's common practice to **scale by sqrt(d_k)**, where d_k is the dimensionality of the key vector.

> [!definition] **Scaling**: prevents the softmax from becoming too large or small.

> [!tip] Use scaling when dealing with self-attention mechanisms.

### Attending to Multiple Relationships
By using multiple attention heads, models can simultaneously consider **several relationships** between tokens. This allows the model to capture a broader range of patterns and improve its ability to generalize.

### Restoring Word Order
Positional encodings are used to **restore word order information**, which is essential for understanding the context in which words appear. Without positional encodings, models would struggle to distinguish between sentences like "dog bites man" and "man bites dog".

> [!warning] No positional encodings = no contextual understanding.

> [!example] "Dog bites man" vs. "Man bites dog": two different meanings.

### The Attention Mechanism: Quadratic Complexity
The full self-attention mechanism has a **quadratic complexity** in sequence length, meaning that as the input sequence grows, so does the computational cost of the attention mechanism.

> [!tip] Use multiple heads or scaling to reduce the complexity of self-attention.

### Exercises

- [ ] Repeat Exercise 9.1 with scores (6, 6, 0) and d_k = 9.
- [ ] Explain why positional encodings are necessary for distinguishing between "dog bites man" and "man bites dog".

## Example: Identifying Largest Weights
In the example given in Section 9.3, the weights assigned to each token are:

(6, 6, 0)

Using this information, we can identify which tokens receive the largest weights.

| Token | Weight |
| --- | --- |
| A    | 6     |
| B    | 6     |

The tokens with weights 6 will be assigned the largest weights, as they have the highest similarity between their query and key vectors.

- [ ] Repeat Exercise 9.1 with scores (6, 6, 0) and d_k = 9 to see how the scaling affects the weights.

## Key takeaways
The Transformer architecture removes recurrence entirely by using attention instead of relying on a single summary vector, allowing it to look back at every encoder state and decide which input positions are relevant for each output step.

• Attention is used instead of recurrent neural networks (RNNs) due to its ability to remove recurrence.
• The Transformer uses self-attention to allow the model to attend to several relationships at once.
• Positional encodings are added to each input embedding to restore word-order information.
• Multi-head attention allows the model to attend to multiple relationships simultaneously.

## Review questions

> [!question] Why did the Transformer architecture replace RNNs in sequence tasks?
> **Answer:** The Transformer replaced RNNs in sequence tasks because it can look back at every encoder state and decide which input positions are relevant for each output step, allowing it to remove recurrence entirely.

> [!question] What is the purpose of scaling by sqrt(d_k) in self-attention?
> **Answer:** Scaling by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing gradients from becoming too small or exploding.

> [!question] How does multi-head attention work in the Transformer architecture?
> **Answer:** Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace.

> [!question] Why is it important to enforce masking in language models?
> **Answer:** Masking is enforced to prevent language models from looking at future tokens; this is done with a causal mask that sets scores (i, j) with j > i to minus infinity.
