<!-- job=paper-v8 backend=mlx seconds=183 calls=8 prompt_tokens=9310 gen_tokens=3025 source_chars=10185 source_tokens=2422 note_chars=10183 metrics={'chars': 10183, 'copy_ratio': 0.218, 'fillers': 0, 'dup_headings': 1, 'sections': 5, 'callouts': 17} -->
# The Power of Attention in Transformers
The Transformer model introduced self-attention as its core mechanism for processing sequential data, revolutionizing the field of NLP with its ability to capture long-range dependencies and complex patterns in input sequences.

> [!summary] Overview
> Self-attention is a mechanism that allows the model to focus on relevant parts of the input sequence by computing a weighted average of value vectors based on query-key similarities. This is achieved through attention mechanisms, which use dot products as their similarity function. Multi-head attention further enhances this process by running multiple attention operations in parallel, each with its own projection matrices. The Transformer also incorporates positional information through learned position embeddings or sine and cosine functions, allowing it to distinguish between different positions in the input sequence. However, without these positional encodings, models struggle to capture complex patterns, such as the difference between "dog bites man" and "man bites dog".

## The Power of Attention in Transformers

The attention mechanism was introduced as an add-on to recurrent encoder-decoder models to address weaknesses of sequential models like RNNs.

### Why Recurrence Can Be a Problem
Computation is inherently sequential in RNNs, which can lead to information about early tokens being lost and long-range dependencies being learned poorly. This is because RNNs process one token at a time, making it difficult for the model to learn relationships between distant tokens.

> [!tip] Think of it like a dictionary (key-value store)
Attention lets the decoder look back at every encoder state and decide which input positions are relevant for each output step. It's like searching through a dictionary to find the most similar words to your query.

### How Attention Works
Each token in the input is represented by a vector x_i of dimension d_model, and three learned linear maps produce:

- **Query** q_i = x_i W^Q: This represents the "interest" or "relevance" of each token.
- **Key** k_i = x_i W^K: This represents the "meaning" or "content" of each token.
- **Value** v_i = x_i W^V: This represents the actual value of each token.

The attention mechanism uses the dot product as its similarity function for attention. The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V (9.1).

### Why Normalization Matters
Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range to prevent gradients from exploding or shrinking.

### Example Time!
Suppose a sequence has three tokens and d_k = 4. For the first token, the raw scores against the three keys are (8, 4, 0). The attention mechanism will calculate the weights for each token based on these similarities.

| Token | Raw Score |
| --- | --- |
| 1    | 8        |
| 2    | 4        |
| 3    | 0        |

The final weights will be calculated by normalizing these raw scores, which will result in a set of weights that represent the relative importance of each token.

## Multi-Head Attention and Positional Information in Transformers

### Scaling Down the Weights
When attention weights are scaled by 1/sqrt(4) = 0.5, they become approximately **(0.87, 0.12, 0.02)**, with the output of token 1 being mostly its own value.

Without scaling, weights would be about **(0.98, 0.02, 0.00)**, making it a "harder" choice.

> [!tip] Think of it this way: scaling down the weights helps to reduce the impact of future tokens on current ones.

### Self-Attention and Cross-Attention
**Self-attention**: every token builds a new representation by gathering information from other tokens in the same sequence.
**Cross-attention**: decoder uses queries from itself, while keys and values come from encoder output.

> [!example] Language models must not look at future tokens; this is enforced with a causal mask.

Before softmax, scores (i, j) with j > i are set to minus infinity, making corresponding weights zero. The same mechanism is used to ignore padding tokens in a batch.

### Multi-Head Attention
The **multi-head attention** runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V.

Each head works with d_k = d_v = 512 / 8 = 64 dimensions; empirically, different heads learn to specialize in tracking previous tokens or syntactic relations.

> [!tip] Think of it this way: multi-head attention allows the model to focus on different aspects simultaneously.

### Positional Information
Attention is permutation-invariant, meaning the model has no idea of word order unless supplied with **positional encoding vectors**.

The original Transformer adds a positional encoding vector to each input embedding using sine and cosine functions of different frequencies.

Low dimensions oscillate quickly, while high dimensions slowly, resulting in every position receiving a distinct pattern.

Many later models instead learn position embeddings directly or use relative schemes like **rotary position embeddings (RoPE)**.

> [!tip] Think of it this way: positional information is crucial for understanding the sequence structure.

### Transformer Layer
A Transformer layer combines two sub-layers: **multi-head self-attention** and a **position-wise feed-forward network (FFN) applied independently to every token**.

- [ ] Review the math behind attention weights scaling

## Self-Attention Magic: how Transformers learn to read

**Attention**: computing a weighted average of value vectors is crucial for understanding what's happening in self-attention.

### How Attention Works
Attention uses ==a softmax over query-key similarities== to compute a weighted average, which helps the model focus on relevant parts of the input sequence.

> [!definition] **Softmax**: a function that outputs probabilities between 0 and 1, used to normalize the output

> [!example] Example with scores (6, 6, 0)
A simple example with scores: 6, 6, 0. The highest score is 6, so the token it corresponds to will receive the largest weight in the attention calculation.

### Multiple Heads for Multi-Relationships
Using multiple heads lets the model ==attend to several relationships at once==, improving its ability to capture complex patterns in the input sequence.

### Residual Connections and LayerNorm
Each block consists of attention + FFN (Fully Featured Network), with residual connections and LayerNorm. These components help stabilize the training process and improve the model's performance.

> [!tip] **Residual Connections**: adding the identity function to each layer helps preserve the information flow during training

> [!tip] **LayerNorm**: normalizing the activations before passing them through a linear transformation helps stabilize the training process

### Cost of Full Self-Attention
The cost of full self-attention is ==quadratic in sequence length==, which can be computationally expensive for long sequences.

> [!warning] **Computational Complexity**: full self-attention has a high computational complexity, making it challenging to train models with very long input sequences.

### Exercises
- 9.1: Repeat worked example using scores (6, 6, 0) and d_k = 9.
- 9.2: Explain why a model without positional encodings cannot distinguish "dog bites man" from "man bites dog".

| Token | Score |
| --- | --- |
| Dog   | 6    |
| Bites | 6    |
| Man   | 0    |

> [!definition] **Token Attention Weights**: the output of the attention mechanism is a vector where each element represents the weight of the corresponding token in the input sequence.

> [!example] Example with scores (6, 6, 0)
The highest score is 6, so the tokens it corresponds to will receive the largest weights in the attention calculation.

## Key takeaways
- The attention mechanism allows the decoder to look back at every encoder state and decide which input positions are relevant for each output step, effectively enabling long-range dependencies to be learned by sequential models like RNNs.
- The Transformer removed recurrence entirely and built the network out of attention and simple feed-forward layers, resulting in a more efficient and scalable model.
- Attention lets the decoder weigh the importance of different tokens in the input sequence, using a softmax over query-key similarities, and computes a weighted average of value vectors.
- Multi-head attention allows the model to attend to several relationships at once, while positional information is permutation-invariant, meaning the model has no idea of word order unless supplied with positional encoding vectors.
- The Transformer layer combines two sub-layers: multi-head self-attention and a position-wise feed-forward network (FFN) applied independently to every token.

## Review questions

> [!question] What is the main advantage of using attention in sequential models like RNNs?
> **Answer:** Attention allows the decoder to look back at every encoder state and decide which input positions are relevant for each output step, enabling long-range dependencies to be learned by sequential models like RNNs.

> [!question] Why does the Transformer use the dot product as its similarity function for attention?
> **Answer:** The Transformer uses the dot product as its similarity function for attention because it is a well-behaved range that keeps the softmax in a well-behaved range to prevent gradients from exploding or shrinking.

> [!question] How does multi-head attention allow the model to attend to several relationships at once?
> **Answer:** Multi-head attention allows the model to attend to several relationships at once by running h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V, and empirically, different heads learn to specialize in tracking previous tokens or syntactic relations.

> [!question] Why is positional information permutation-invariant in the Transformer?
> **Answer:** Positional information is permutation-invariant in the Transformer because it uses sine and cosine functions of different frequencies to create a unique pattern for every position, regardless of word order.
