<!-- job=paper-v7 backend=mlx seconds=201 calls=8 prompt_tokens=9562 gen_tokens=3258 source_chars=10185 source_tokens=2422 note_chars=9989 metrics={'chars': 9989, 'copy_ratio': 0.169, 'fillers': 0, 'dup_headings': 0, 'sections': 7, 'callouts': 12} -->
# The Magic of Self-Attention in Transformers

Did you know that self-attention is a technique used by the transformer model to compute a weighted average of value vectors based on similarities between query-key pairs? This allows the model to focus on the most relevant relationships between tokens, capturing complex patterns in the data.

> [!summary] Overview
> Self-attention is a key component of the Transformer architecture, enabling it to attend to multiple relationships between tokens simultaneously. By using multiple attention heads and scaling down the weights, self-attention helps the model focus on relevant information. Positional encodings are used to preserve the order of words in the input sequence, while residual connections and LayerNorm stabilize the training process. Multi-head attention allows the model to learn specialized representations for each head, improving its ability to track previous tokens or follow syntactic relations.

## The Power of Attention in Transformers

The Transformer model introduced attention as an add-on to recurrent encoder-decoder models to overcome weaknesses of sequential RNNs.

Traditional RNNs have two main issues:

*   **Sequential Computation**: information about early tokens must survive many repeated applications of the model.
*   **Surviving Early Tokens**: traditional RNNs struggle to keep track of important information from earlier tokens.

### How Attention Works
Attention can be thought of as a soft dictionary lookup, where the query is compared with every key, producing similarity scores that become weights summing to one.

> [!definition] Soft Dictionary Lookup
>
> The attention mechanism uses a query vector q_i, a set of key vectors k_i, and a value vector v_i to produce a probability distribution over the input positions.

Each token in the input is represented by a vector x_i of dimension d_model. With learned linear maps, we get:

*   **Query Vector**: q_i = Linear(x_i)
*   **Key Vector**: k_i = Linear(x_i)
*   **Value Vector**: v_i = Linear(x_i)

The complete operation is written as Attention(Q, K, V) = softmax( Q K^T / sqrt(d_k) ) V (9.1), where Q, K, and V are matrices representing the query, key, and value vectors respectively.

### The Dot Product: A Measure of Similarity
The dot product is used as the similarity function, resulting in an n x n matrix measuring how strongly token i attends to token j.

> [!tip] Understanding the Dot Product
>
> The dot product measures the cosine similarity between two vectors, producing a value between -1 and 1 that represents the strength of their similarity.

### Applying Softmax for Probability Distribution
The softmax is applied row by row, producing a probability distribution over the n positions, which is then multiplied by the value vectors according to those probabilities.

Dividing by sqrt(d_k) restores unit variance and keeps the softmax in a well-behaved range, preventing gradients from shrinking or exploding.

### Example: Calculating Raw Scores
Suppose a sequence has three tokens and d_k = 4. For the first token, the raw scores against the three keys are (8, 4, 0).

| Token | Score |
|---|---|
| 1   | 8    |
| 2   | 4    |
| 3   | 0    |

- [ ] Practice calculating attention scores for different scenarios

## How Transformers Use Multi-Head Attention with Positional Information

Transformers rely on **multi-head attention**, a technique that allows the model to focus on different aspects of the input sequence simultaneously. This is achieved through **self-attention** and **cross-attention**, both of which are used in encoder-decoder models.

### Scaling Down Attention Weights
When computing attention weights, we need to scale them down to avoid choosing between tokens that are too similar. Without scaling, weights would be about (0.98, 0.02, 0.00), making it "harder" to choose between tokens. However, after scaling by 1/sqrt(4) = 0.5, attention weights become approximately (0.87, 0.12, 0.02).

### Self-Attention and Cross-Attention
Self-attention occurs when Q, K, and V are computed from the same sequence, where each token builds a new representation by gathering information from other tokens in the same sentence. Cross-attention is used in encoder-decoder models, where queries come from the decoder and keys and values come from the encoder output.

> [!tip] Don't forget to mask future tokens
Masking is enforced with a causal mask before softmax, setting scores (i, j) with j > i to minus infinity to prevent future tokens from influencing current ones.

### Multi-Head Attention Operations
Multi-head attention runs h attention operations in parallel, each with its own projection matrices W_i^Q, W_i^K, W_i^V that map into a smaller subspace. The outputs are concatenated and passed through a final linear map W^O: MultiHead(Q, K, V) = Concat(head_1, ..., head_h) W^O.

| Head | Q, K, V Dimensions |
|---|---|
| 1   | d_model = 512        |
| 2   | d_k = d_v = 64        |
| ... | ...                  |

### Empirical Results
Empirical results show that different heads learn to specialize in tracking previous tokens, linking pronouns to nouns, or following syntactic relations. This is achieved through the use of positional encoding vectors and the Transformer's ability to focus on different aspects of the input sequence.

> [!warning] Be aware of permutation-invariance
Attention is permutation-invariant, meaning shuffling input tokens does not change output tokens unless a positional encoding vector is supplied.

### Positional Information
The Transformer adds a positional encoding vector to each input embedding using sine and cosine functions of different frequencies. Low-dimensional positions oscillate quickly, while high-dimensional positions slowly oscillate, resulting in distinct patterns for every position.

- [ ] Learn about rotary position embeddings (RoPE)

## The Magic of Self-Attention in Transformers

### **Self-attention**: Weighing the importance of words
**Self-attention** is a technique used in Transformers to compute a weighted average of value vectors, based on similarities between query-key pairs. ==This allows the model to focus on the most relevant relationships between tokens==.

```python
import numpy as np

## Example scores and d_k values
scores = [6, 6, 0]
d_k = 9

## Compute attention weights using softmax
weights = np.softmax(scores / d_k)

print(weights)
```

### **Scaling**: Preventing the softmax from saturating
To prevent the softmax function from saturating at 1s for all query-key similarities, **scaling** is used. This involves dividing by sqrt(d_k), where d_k is the dimensionality of the key vector.

> [!tip] Scaling helps avoid division by zero and prevents the softmax from becoming too dominant.

### **Multiple heads**: Attending to multiple relationships simultaneously
By using multiple attention heads, a Transformer model can attend to several relationships between tokens simultaneously. ==This allows the model to capture complex patterns in the data==.

### **Positional encodings**: Restoring word-order information
To preserve the order of words in the input sequence, **positional encodings** are used. These encodings provide a way for the model to understand the relative positions of different tokens.

> [!warning] Without positional encodings, models may struggle with tasks that require understanding of sequential relationships.

### **Block structure**: Attention + FFN with residual connections and LayerNorm
The Transformer architecture is organized into blocks, each consisting of attention and feed-forward neural network (FFN) components. ==Residual connections and LayerNorm help stabilize the training process==.

- [ ] Try implementing the self-attention mechanism using multiple heads.
- [ ] Understand how positional encodings can affect the performance of a model on sequential data tasks.

> [!example] The importance of self-attention in distinguishing "dog bites man" from "man bites dog"
Without positional encodings, models may struggle to distinguish between two sentences that differ only by word order. ==Self-attention helps focus on relevant relationships between tokens==.

### **Cost of self-attention**: Quadratic in sequence length (O(n^2 d))
The self-attention mechanism has a computational cost proportional to the square of the sequence length and the dimensionality of the key vector. ==This can be a significant bottleneck for long sequences or high-dimensional inputs==.

- [ ] Investigate techniques for reducing the computational complexity of self-attention mechanisms.
- [ ] Explore alternative attention mechanisms that may offer better performance on certain tasks.

## Key takeaways
- The Transformer model's attention mechanism allows the decoder to selectively focus on relevant parts of the input sequence, enabling it to better understand and generate coherent output.
- Attention is a crucial component of the Transformer model, enabling it to attend to multiple relationships simultaneously and learn complex patterns in data.
- Positional encodings are used to restore word-order information in the input sequence, allowing the model to distinguish between different sentences or phrases.
- Multi-head attention enables the model to attend to multiple relationships at once, improving its ability to capture complex patterns and nuances in data.
- The Transformer model's block structure consists of attention + FFN, with residual connections and LayerNorm, which helps to improve its training speed and stability.

## Review questions

> [!question] Why is it difficult for a model without positional encodings to distinguish "dog bites man" from "man bites dog"?

> [!question] Explain why the Transformer model's attention mechanism is permutation-invariant.

> [!question] What is the cost of self-attention in terms of sequence length?

> [!question] Why is scaling by sqrt(d_k) used to prevent gradients from shrinking or exploding during training?
